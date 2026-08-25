-- ============================================================================
--  FPTM — Inscripciones por EQUIPOS (Copa Olímpica 2026)
--  Ejecutar en: Supabase → SQL Editor  (seguro de re-ejecutar)
--
--  Por qué una tabla aparte y no `insc_registro`: la unidad de inscripción de
--  la Copa es el equipo de 2, no la persona. `insc_registro` tiene
--  UNIQUE (torneo, member_id) — una fila = un jugador — y sus categorías son
--  individuales, con horario, edad y sexo. Nada de eso aplica aquí.
--
--  Qué crea:
--    public.insc_divisiones        — configuración de divisiones por torneo
--    public.insc_equipos           — un equipo inscrito = una fila
--    public.insc_equipos_publico   — vista de solo lectura para el portal
--    public.insc_equipos_cupos     — conteo de cupos por división
--    public.inscribir_equipo(...)  — alta transaccional con control de cupo
--    public.insc_equipos_liberar() — expira reservas y promueve lista de espera
--
--  Modelo de cupos (decidido con la federación):
--    · El cupo se RESERVA al inscribir y se libera solo si no entra el pago
--      dentro de la ventana (48 h por defecto).
--    · Al liberarse un cupo entra automáticamente el primero de la lista de
--      espera de esa división.
--    · La división se deriva del rating combinado y NO se puede escoger.
--    · El rating de ambos jugadores se congela al momento de inscribir.
--    · Un jugador solo puede estar en un equipo en todo el torneo.
--
--  Nota sobre esa última regla: se garantiza dentro de inscribir_equipo(),
--  que corre bajo un advisory lock por torneo. El público no puede insertar
--  directamente (no tiene GRANT), así que toda alta pasa por ahí. Un INSERT
--  manual de admin sí podría saltársela — por eso el panel admin valida antes.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. CONFIGURACIÓN DE DIVISIONES
--    rating_min / rating_max son inclusivos; NULL = sin piso / sin techo.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.insc_divisiones (
  torneo      TEXT    NOT NULL,
  division    TEXT    NOT NULL,
  nombre      TEXT    NOT NULL,
  rating_min  INTEGER,
  rating_max  INTEGER,
  precio      NUMERIC(8,2) NOT NULL,
  max_equipos INTEGER NOT NULL,
  orden       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (torneo, division)
);

INSERT INTO public.insc_divisiones
  (torneo, division, nombre, rating_min, rating_max, precio, max_equipos, orden)
VALUES
  ('Copa Olímpica 2026', 'div1', 'División 1', 3800, NULL,  100.00, 12, 1),
  ('Copa Olímpica 2026', 'div2', 'División 2', 3400, 3799,   80.00, 20, 2),
  ('Copa Olímpica 2026', 'div3', 'División 3', NULL, 3399,   70.00, 32, 3)
ON CONFLICT (torneo, division) DO UPDATE
  SET nombre      = EXCLUDED.nombre,
      rating_min  = EXCLUDED.rating_min,
      rating_max  = EXCLUDED.rating_max,
      precio      = EXCLUDED.precio,
      max_equipos = EXCLUDED.max_equipos,
      orden       = EXCLUDED.orden;


-- ---------------------------------------------------------------------------
-- 2. EQUIPOS
--
--  estado:
--    reservado           cupo tomado, esperando el pago (reserva_expira manda)
--    confirmado          pago recibido — el cupo ya no expira
--    lista_espera        la división estaba llena; entra si se libera un cupo
--    pendiente_division  falta rating de algún invitado; no ocupa cupo todavía
--    expirado            venció la reserva sin pago; el cupo se liberó
--    cancelado           dado de baja por la federación o por el capitán
--
--  Solo `reservado` y `confirmado` ocupan cupo.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.insc_equipos (
  id               BIGSERIAL PRIMARY KEY,
  torneo           TEXT NOT NULL,
  division         TEXT,
  estado           TEXT NOT NULL DEFAULT 'reservado',

  nombre_equipo    TEXT,
  club             TEXT,

  cap_member_id    INTEGER,
  cap_nombre       TEXT NOT NULL,
  cap_rating       INTEGER,
  cap_invitado     BOOLEAN NOT NULL DEFAULT FALSE,
  cap_email        TEXT,
  cap_tel          TEXT,

  comp_member_id   INTEGER,
  comp_nombre      TEXT NOT NULL,
  comp_rating      INTEGER,
  comp_invitado    BOOLEAN NOT NULL DEFAULT FALSE,

  rating_combinado INTEGER,
  costo            NUMERIC(8,2) NOT NULL DEFAULT 0,
  monto_pagado     NUMERIC(8,2) NOT NULL DEFAULT 0,
  pagado           BOOLEAN NOT NULL DEFAULT FALSE,
  referencia       TEXT,

  reserva_expira   TIMESTAMPTZ,
  notas            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT insc_equipos_estado_chk CHECK (estado IN
    ('reservado','confirmado','lista_espera','pendiente_division','expirado','cancelado'))
);

CREATE INDEX IF NOT EXISTS insc_equipos_torneo_idx   ON public.insc_equipos (torneo);
CREATE INDEX IF NOT EXISTS insc_equipos_division_idx ON public.insc_equipos (torneo, division, estado);
CREATE INDEX IF NOT EXISTS insc_equipos_cap_idx      ON public.insc_equipos (torneo, cap_member_id);
CREATE INDEX IF NOT EXISTS insc_equipos_comp_idx     ON public.insc_equipos (torneo, comp_member_id);


-- ---------------------------------------------------------------------------
-- 3. AJUSTES OPERATIVOS (viven en app_settings para poder cambiarlos sin deploy)
--      insc_equipos_reserva_horas — ventana para pagar antes de perder el cupo
--      insc_equipos_cierre        — fecha límite de inscripción (ISO 8601)
-- ---------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value) VALUES
  ('insc_equipos_reserva_horas', '48'),
  ('insc_equipos_cierre',        '2026-09-11T22:00:00-04:00')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.insc_equipos_reserva_horas()
RETURNS INTEGER
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v TEXT;
BEGIN
  SELECT value INTO v FROM public.app_settings WHERE key = 'insc_equipos_reserva_horas';
  RETURN GREATEST(1, COALESCE(NULLIF(btrim(v), '')::INTEGER, 48));
EXCEPTION WHEN OTHERS THEN
  RETURN 48;   -- valor mal escrito en app_settings: no tumbamos la inscripción
END;
$$;

-- Nombre normalizado — así "  josé  PÉREZ " y "José Pérez" son el mismo invitado
CREATE OR REPLACE FUNCTION public.insc_nombre_norm(raw TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT lower(btrim(regexp_replace(coalesce(raw, ''), '\s+', ' ', 'g')));
$$;


-- ---------------------------------------------------------------------------
-- 4. LIBERAR CUPOS
--    Expira las reservas vencidas que nunca recibieron pago y promueve la
--    lista de espera de cada división al espacio que quedó libre.
--    Se llama sola al inicio de inscribir_equipo(); el admin también puede
--    invocarla a mano desde el panel.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insc_equipos_liberar(p_torneo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_expirados  INTEGER := 0;
  v_promovidos INTEGER := 0;
  v_horas      INTEGER := public.insc_equipos_reserva_horas();
  v_libres     INTEGER;
  v_id         BIGINT;
  d            RECORD;
BEGIN
  UPDATE public.insc_equipos
     SET estado = 'expirado', updated_at = NOW()
   WHERE torneo = p_torneo
     AND estado = 'reservado'
     AND reserva_expira IS NOT NULL
     AND reserva_expira < NOW()
     AND COALESCE(monto_pagado, 0) = 0;
  GET DIAGNOSTICS v_expirados = ROW_COUNT;

  FOR d IN SELECT division, max_equipos FROM public.insc_divisiones
            WHERE torneo = p_torneo ORDER BY orden LOOP
    LOOP
      SELECT d.max_equipos - COUNT(*) INTO v_libres
        FROM public.insc_equipos
       WHERE torneo = p_torneo AND division = d.division
         AND estado IN ('reservado', 'confirmado');
      EXIT WHEN v_libres <= 0;

      SELECT id INTO v_id FROM public.insc_equipos
       WHERE torneo = p_torneo AND division = d.division AND estado = 'lista_espera'
       ORDER BY created_at ASC, id ASC
       LIMIT 1;
      EXIT WHEN v_id IS NULL;

      UPDATE public.insc_equipos
         SET estado         = 'reservado',
             reserva_expira = NOW() + (v_horas || ' hours')::INTERVAL,
             updated_at     = NOW()
       WHERE id = v_id;
      v_promovidos := v_promovidos + 1;
      v_id := NULL;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('expirados', v_expirados, 'promovidos', v_promovidos);
END;
$$;


-- ---------------------------------------------------------------------------
-- 5. ALTA DE EQUIPO  (única puerta de entrada del público)
--
--  Todo corre dentro de una transacción con advisory lock por torneo, así que
--  dos capitanes pulsando "Inscribir" en el mismo instante se serializan: es
--  imposible pasarse del cupo o colar al mismo jugador en dos equipos.
--
--  Devuelve JSON. Los errores esperables vuelven como {"ok": false, ...} para
--  que el portal los muestre tal cual, en vez de reventar con un 500.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inscribir_equipo(
  p_torneo         TEXT,
  p_cap_member_id  INTEGER,
  p_cap_nombre     TEXT,
  p_cap_rating     INTEGER,
  p_comp_member_id INTEGER,
  p_comp_nombre    TEXT,
  p_comp_rating    INTEGER,
  p_cap_invitado   BOOLEAN DEFAULT FALSE,
  p_comp_invitado  BOOLEAN DEFAULT FALSE,
  p_nombre_equipo  TEXT DEFAULT NULL,
  p_club           TEXT DEFAULT NULL,
  p_cap_email      TEXT DEFAULT NULL,
  p_cap_tel        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_abierto   TEXT;
  v_cierre    TEXT;
  v_cap_norm  TEXT := public.insc_nombre_norm(p_cap_nombre);
  v_comp_norm TEXT := public.insc_nombre_norm(p_comp_nombre);
  v_combinado INTEGER;
  v_division  TEXT;
  v_div_nombre TEXT;
  v_max       INTEGER;
  v_ocupados  INTEGER;
  v_estado    TEXT;
  v_expira    TIMESTAMPTZ;
  v_costo     NUMERIC(8,2) := 0;
  v_posicion  INTEGER;
  v_choque    RECORD;
  v_id        BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_equipos:' || p_torneo));

  -- ── Puertas: inscripciones abiertas y dentro de la fecha límite ──────────
  SELECT value INTO v_abierto FROM public.app_settings WHERE key = 'inscripciones_open';
  IF COALESCE(v_abierto, 'false') <> 'true' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'cerradas',
      'error', 'Las inscripciones no están abiertas en este momento.');
  END IF;

  SELECT value INTO v_cierre FROM public.app_settings WHERE key = 'insc_equipos_cierre';
  IF v_cierre IS NOT NULL AND btrim(v_cierre) <> '' THEN
    BEGIN
      IF NOW() > v_cierre::TIMESTAMPTZ THEN
        RETURN jsonb_build_object('ok', false, 'codigo', 'fecha_limite',
          'error', 'La fecha límite de inscripción ya pasó.');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- fecha mal escrita en app_settings: no bloqueamos por eso
    END;
  END IF;

  -- ── Validación básica ────────────────────────────────────────────────────
  IF v_cap_norm = '' OR v_comp_norm = '' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'incompleto',
      'error', 'El equipo necesita dos jugadores con nombre.');
  END IF;

  IF (p_cap_member_id IS NOT NULL AND p_cap_member_id = p_comp_member_id)
     OR (p_cap_member_id IS NULL AND p_comp_member_id IS NULL AND v_cap_norm = v_comp_norm) THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'mismo_jugador',
      'error', 'El capitán y su compañero no pueden ser la misma persona.');
  END IF;

  -- ── Liberar lo vencido antes de contar cupos ─────────────────────────────
  PERFORM public.insc_equipos_liberar(p_torneo);

  -- ── Un jugador, un solo equipo en todo el torneo ─────────────────────────
  SELECT id, nombre_equipo, cap_nombre, comp_nombre, estado,
         CASE WHEN (cap_member_id IS NOT NULL AND cap_member_id IN (p_cap_member_id, p_comp_member_id))
                OR (cap_member_id IS NULL AND public.insc_nombre_norm(cap_nombre) IN (v_cap_norm, v_comp_norm))
              THEN cap_nombre ELSE comp_nombre END AS jugador
    INTO v_choque
    FROM public.insc_equipos
   WHERE torneo = p_torneo
     AND estado IN ('reservado', 'confirmado', 'lista_espera', 'pendiente_division')
     AND (
          (cap_member_id  IS NOT NULL AND cap_member_id  IN (p_cap_member_id, p_comp_member_id))
       OR (comp_member_id IS NOT NULL AND comp_member_id IN (p_cap_member_id, p_comp_member_id))
       OR (cap_member_id  IS NULL AND public.insc_nombre_norm(cap_nombre)  IN (v_cap_norm, v_comp_norm))
       OR (comp_member_id IS NULL AND public.insc_nombre_norm(comp_nombre) IN (v_cap_norm, v_comp_norm))
     )
   LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'ya_inscrito',
      'jugador', v_choque.jugador,
      'equipo',  COALESCE(NULLIF(v_choque.nombre_equipo, ''),
                          v_choque.cap_nombre || ' / ' || v_choque.comp_nombre),
      'error', v_choque.jugador || ' ya está inscrito/a en otro equipo de este torneo.');
  END IF;

  -- ── División por rating combinado (congelado en este instante) ───────────
  IF p_cap_rating IS NOT NULL AND p_comp_rating IS NOT NULL THEN
    v_combinado := p_cap_rating + p_comp_rating;

    SELECT division, nombre, precio, max_equipos
      INTO v_division, v_div_nombre, v_costo, v_max
      FROM public.insc_divisiones
     WHERE torneo = p_torneo
       AND (rating_min IS NULL OR v_combinado >= rating_min)
       AND (rating_max IS NULL OR v_combinado <= rating_max)
     ORDER BY orden LIMIT 1;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'codigo', 'sin_division',
        'error', 'No hay división configurada para un rating combinado de ' || v_combinado || '.');
    END IF;

    SELECT COUNT(*) INTO v_ocupados FROM public.insc_equipos
     WHERE torneo = p_torneo AND division = v_division
       AND estado IN ('reservado', 'confirmado');

    IF v_ocupados < v_max THEN
      v_estado := 'reservado';
      v_expira := NOW() + (public.insc_equipos_reserva_horas() || ' hours')::INTERVAL;
    ELSE
      v_estado := 'lista_espera';
      v_expira := NULL;
    END IF;
  ELSE
    -- Invitado sin rating: el equipo entra, pero la federación le asigna
    -- división a mano. Mientras tanto no ocupa cupo de nadie.
    v_estado := 'pendiente_division';
    v_expira := NULL;
  END IF;

  INSERT INTO public.insc_equipos (
    torneo, division, estado, nombre_equipo, club,
    cap_member_id, cap_nombre, cap_rating, cap_invitado, cap_email, cap_tel,
    comp_member_id, comp_nombre, comp_rating, comp_invitado,
    rating_combinado, costo, reserva_expira
  ) VALUES (
    p_torneo, v_division, v_estado, NULLIF(btrim(COALESCE(p_nombre_equipo, '')), ''),
    NULLIF(btrim(COALESCE(p_club, '')), ''),
    p_cap_member_id, btrim(p_cap_nombre), p_cap_rating, COALESCE(p_cap_invitado, FALSE),
    NULLIF(btrim(COALESCE(p_cap_email, '')), ''), NULLIF(btrim(COALESCE(p_cap_tel, '')), ''),
    p_comp_member_id, btrim(p_comp_nombre), p_comp_rating, COALESCE(p_comp_invitado, FALSE),
    v_combinado, v_costo, v_expira
  ) RETURNING id INTO v_id;

  IF v_estado = 'lista_espera' THEN
    SELECT COUNT(*) INTO v_posicion FROM public.insc_equipos
     WHERE torneo = p_torneo AND division = v_division AND estado = 'lista_espera'
       AND id <= v_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_id,
    'estado', v_estado,
    'division', v_division,
    'division_nombre', v_div_nombre,
    'rating_combinado', v_combinado,
    'costo', v_costo,
    'reserva_expira', v_expira,
    'posicion_espera', v_posicion,
    'cupos_restantes', CASE WHEN v_estado = 'reservado'
                            THEN v_max - v_ocupados - 1 ELSE 0 END
  );
END;
$$;


-- ---------------------------------------------------------------------------
-- 6. VISTAS PÚBLICAS
--    El portal necesita mostrar equipos y cupos sin exponer email, teléfono,
--    referencia de pago ni montos. La tabla base queda cerrada al público y
--    estas vistas son la única ventana: no es disciplina del cliente, es que
--    las columnas sensibles literalmente no existen aquí.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.insc_equipos_publico
WITH (security_invoker = off) AS
SELECT
  e.id, e.torneo, e.division, e.estado,
  e.nombre_equipo, e.club,
  e.cap_nombre,  e.cap_rating,
  e.comp_nombre, e.comp_rating,
  e.rating_combinado,
  e.created_at
FROM public.insc_equipos e
WHERE e.estado IN ('reservado', 'confirmado', 'lista_espera', 'pendiente_division');

CREATE OR REPLACE VIEW public.insc_equipos_cupos
WITH (security_invoker = off) AS
SELECT
  d.torneo, d.division, d.nombre, d.rating_min, d.rating_max,
  d.precio, d.max_equipos, d.orden,
  COUNT(*) FILTER (WHERE e.estado IN ('reservado', 'confirmado'))       AS ocupados,
  GREATEST(d.max_equipos
    - COUNT(*) FILTER (WHERE e.estado IN ('reservado', 'confirmado')), 0) AS disponibles,
  COUNT(*) FILTER (WHERE e.estado = 'lista_espera')                     AS en_espera,
  COUNT(*) FILTER (WHERE e.estado = 'confirmado')                       AS confirmados
FROM public.insc_divisiones d
LEFT JOIN public.insc_equipos e
       ON e.torneo = d.torneo AND e.division = d.division
GROUP BY d.torneo, d.division, d.nombre, d.rating_min, d.rating_max,
         d.precio, d.max_equipos, d.orden;


-- ---------------------------------------------------------------------------
-- 7. updated_at automático
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insc_equipos_touch()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS insc_equipos_touch_trg ON public.insc_equipos;
CREATE TRIGGER insc_equipos_touch_trg
  BEFORE UPDATE ON public.insc_equipos
  FOR EACH ROW EXECUTE FUNCTION public.insc_equipos_touch();


-- ---------------------------------------------------------------------------
-- 8. PERMISOS
--    anon  → solo lee las vistas y la config de divisiones, y solo puede
--            inscribir a través de la función (que valida cupo y duplicados).
--    admin → acceso completo a la tabla, como en el resto del panel.
-- ---------------------------------------------------------------------------
ALTER TABLE public.insc_equipos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insc_divisiones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_all_insc_equipos ON public.insc_equipos;
CREATE POLICY admin_all_insc_equipos
  ON public.insc_equipos FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS lectura_insc_divisiones ON public.insc_divisiones;
CREATE POLICY lectura_insc_divisiones
  ON public.insc_divisiones FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS admin_write_insc_divisiones ON public.insc_divisiones;
CREATE POLICY admin_write_insc_divisiones
  ON public.insc_divisiones FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- Supabase concede SELECT a anon por defecto en public — aquí se revoca a mano.
REVOKE ALL     ON public.insc_equipos    FROM anon;
GRANT  SELECT  ON public.insc_divisiones TO   anon, authenticated;
GRANT  ALL     ON public.insc_equipos    TO   authenticated;
GRANT  SELECT  ON public.insc_equipos_publico TO anon, authenticated;
GRANT  SELECT  ON public.insc_equipos_cupos   TO anon, authenticated;
GRANT  USAGE, SELECT ON SEQUENCE public.insc_equipos_id_seq TO authenticated;

GRANT EXECUTE ON FUNCTION public.inscribir_equipo(
  TEXT, INTEGER, TEXT, INTEGER, INTEGER, TEXT, INTEGER,
  BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insc_equipos_liberar(TEXT)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.insc_equipos_reserva_horas()    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insc_nombre_norm(TEXT)          TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 9. VERIFICACIÓN
-- ---------------------------------------------------------------------------
SELECT division, nombre, precio, max_equipos, ocupados, disponibles, en_espera
  FROM public.insc_equipos_cupos
 WHERE torneo = 'Copa Olímpica 2026'
 ORDER BY orden;
