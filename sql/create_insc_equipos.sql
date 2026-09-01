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
--    public.insc_equipos_liberar() — promueve la lista de espera a huecos libres
--
--  Modelo de cupos (decidido con la federación):
--    · El cupo se RESERVA al inscribir. Hay 48 h para pagar, pero pasado el
--      plazo el cupo NO se pierde solo: queda marcado en rojo y la FPTM
--      decide si lo suelta. Ninguna inscripción desaparece sin que una
--      persona lo mande.
--    · Al liberarse un cupo (por cancelación) entra automáticamente el
--      primero de la lista de espera de esa división.
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
  -- Reserva de cupo sin pareja: solo donde la federación la habilite, y solo
  -- para jugadores por encima de cierto rating. Ver sección 5b.
  permite_reserva_solo BOOLEAN NOT NULL DEFAULT FALSE,
  reserva_rating_min   INTEGER,
  PRIMARY KEY (torneo, division)
);

-- Instalaciones previas: añadir las columnas sin tocar los datos
ALTER TABLE public.insc_divisiones
  ADD COLUMN IF NOT EXISTS permite_reserva_solo BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS reserva_rating_min   INTEGER;

INSERT INTO public.insc_divisiones
  (torneo, division, nombre, rating_min, rating_max, precio, max_equipos, orden,
   permite_reserva_solo, reserva_rating_min)
VALUES
  ('Copa Olímpica 2026', 'div1', 'División 1', 3800, NULL,  100.00, 12, 1, TRUE,  2000),
  ('Copa Olímpica 2026', 'div2', 'División 2', 3400, 3799,   80.00, 20, 2, FALSE, NULL),
  ('Copa Olímpica 2026', 'div3', 'División 3', NULL, 3399,   70.00, 32, 3, FALSE, NULL)
ON CONFLICT (torneo, division) DO UPDATE
  SET nombre      = EXCLUDED.nombre,
      rating_min  = EXCLUDED.rating_min,
      rating_max  = EXCLUDED.rating_max,
      precio      = EXCLUDED.precio,
      max_equipos = EXCLUDED.max_equipos,
      orden       = EXCLUDED.orden,
      permite_reserva_solo = EXCLUDED.permite_reserva_solo,
      reserva_rating_min   = EXCLUDED.reserva_rating_min;


-- ---------------------------------------------------------------------------
-- 2. EQUIPOS
--
--  estado:
--    reservado            cupo tomado, esperando el pago (reserva_expira manda)
--    confirmado           pago recibido — el cupo ya no expira
--    esperando_companero  cupo comprado sin pareja todavía (ver sección 5b)
--    revision_tecnica     nombró pareja que no llega al mínimo de la división;
--                         lo resuelve la Dirección Técnica
--    lista_espera         la división estaba llena; entra si se libera un cupo
--    pendiente_division   falta rating de algún invitado; no ocupa cupo todavía
--    expirado             en desuso: ya nada expira solo. Se conserva por las
--                         filas antiguas y para poder restaurarlas.
--    cancelado            dado de baja por la federación o por el capitán
--    credito              cupo liberado y dinero a favor del jugador
--
--  Qué ocupa cupo lo dice insc_equipo_ocupa_cupo(), no una lista repetida en
--  cinco sitios: al añadir un estado nuevo, esa función es el único lugar que
--  hay que revisar.
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
  comp_nombre      TEXT,          -- NULL mientras el cupo espera compañero
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

  credito          NUMERIC(8,2) NOT NULL DEFAULT 0,

  CONSTRAINT insc_equipos_estado_chk CHECK (estado IN
    ('reservado','confirmado','esperando_companero','revision_tecnica',
     'lista_espera','pendiente_division','expirado','cancelado','credito'))
);

-- Instalaciones previas: subir el esquema sin perder filas
ALTER TABLE public.insc_equipos
  ADD COLUMN IF NOT EXISTS credito NUMERIC(8,2) NOT NULL DEFAULT 0;
ALTER TABLE public.insc_equipos ALTER COLUMN comp_nombre DROP NOT NULL;
ALTER TABLE public.insc_equipos DROP CONSTRAINT IF EXISTS insc_equipos_estado_chk;
ALTER TABLE public.insc_equipos ADD CONSTRAINT insc_equipos_estado_chk CHECK (estado IN
  ('reservado','confirmado','esperando_companero','revision_tecnica',
   'lista_espera','pendiente_division','expirado','cancelado','credito'));


-- ¿Este estado ocupa uno de los cupos de la división?
CREATE OR REPLACE FUNCTION public.insc_equipo_ocupa_cupo(p_estado TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT p_estado IN ('reservado','confirmado','esperando_companero','revision_tecnica');
$$;

-- ¿Sigue vivo en el torneo? (ocupa cupo, o espera a que se libere uno)
CREATE OR REPLACE FUNCTION public.insc_equipo_activo(p_estado TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT p_estado IN ('reservado','confirmado','esperando_companero','revision_tecnica',
                      'lista_espera','pendiente_division');
$$;

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
-- 4. PROMOVER LA LISTA DE ESPERA
--
--    Decisión de la federación: una reserva vencida NO se cancela sola. El
--    equipo conserva su cupo pase el tiempo que pase; el portal y el panel lo
--    marcan en rojo para que la FPTM lo persiga, y si hay que soltarlo, lo
--    suelta una persona con el botón de cancelar.
--
--    Consecuencia asumida: en una división llena, la lista de espera solo
--    avanza cuando el admin cancela a alguien. Esta función ya no expira
--    nada — solo mueve la espera al hueco que exista.
--
--    Se llama sola al inicio de inscribir_equipo() y tras cada cancelación.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insc_equipos_liberar(p_torneo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_promovidos INTEGER := 0;
  v_vencidas   INTEGER := 0;
  v_horas      INTEGER := public.insc_equipos_reserva_horas();
  v_libres     INTEGER;
  v_id         BIGINT;
  d            RECORD;
BEGIN
  -- Cuántas reservas están fuera de plazo sin pagar. No se tocan: es el
  -- número que el panel usa para saber a quién hay que llamar.
  SELECT COUNT(*) INTO v_vencidas
    FROM public.insc_equipos
   WHERE torneo = p_torneo
     AND estado IN ('reservado', 'esperando_companero')
     AND reserva_expira IS NOT NULL
     AND reserva_expira < NOW()
     AND COALESCE(monto_pagado, 0) = 0;

  FOR d IN SELECT division, max_equipos FROM public.insc_divisiones
            WHERE torneo = p_torneo ORDER BY orden LOOP
    LOOP
      SELECT d.max_equipos - COUNT(*) INTO v_libres
        FROM public.insc_equipos
       WHERE torneo = p_torneo AND division = d.division
         AND public.insc_equipo_ocupa_cupo(estado);
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

  RETURN jsonb_build_object('promovidos', v_promovidos, 'vencidas_sin_pago', v_vencidas);
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
     AND public.insc_equipo_activo(estado)
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
       AND public.insc_equipo_ocupa_cupo(estado);

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
-- 5b. RESERVAR CUPO SIN PAREJA  ("comprar un equipo")
--
--  Un jugador fuerte quiere asegurar su sitio en División 1 antes de tener
--  con quién jugar. Paga el cupo, lo retiene, y nombra al compañero después.
--
--  Lo que compra es un CUPO CONDICIONADO, no el derecho a jugar División 1
--  con cualquiera: la división sigue saliendo del rating combinado. Si al
--  final la pareja no llega al mínimo, el equipo pasa a revisión de la
--  Dirección Técnica, que decide si lo aprueba o lo baja de división.
--
--  Quién puede: solo divisiones con permite_reserva_solo, y solo jugadores
--  por encima de reserva_rating_min. Ese rating se lee de "Base de Datos",
--  no del navegador — si no, cualquiera se manda un 2000 y toma un cupo de
--  los 12.
-- ---------------------------------------------------------------------------

-- Rating vigente del jugador según la federación. NULL si no hay dato.
CREATE OR REPLACE FUNCTION public.insc_rating_federativo(p_member_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v INTEGER;
BEGIN
  IF p_member_id IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(b."New Rating", b."Rating") INTO v
    FROM public."Base de Datos" b WHERE b."Member ID" = p_member_id;
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;


CREATE OR REPLACE FUNCTION public.reservar_cupo_solo(
  p_torneo        TEXT,
  p_member_id     INTEGER,
  p_nombre        TEXT,
  p_division      TEXT,
  p_email         TEXT DEFAULT NULL,
  p_tel           TEXT DEFAULT NULL,
  p_nombre_equipo TEXT DEFAULT NULL,
  p_club          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_abierto  TEXT;
  v_cierre   TEXT;
  v_div      RECORD;
  v_rating   INTEGER;
  v_ocupados INTEGER;
  v_choque   RECORD;
  v_expira   TIMESTAMPTZ;
  v_id       BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_equipos:' || p_torneo));

  IF p_member_id IS NULL OR public.insc_nombre_norm(p_nombre) = '' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'incompleto',
      'error', 'Solo jugadores registrados en la FPTM pueden reservar un cupo.');
  END IF;

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
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  SELECT * INTO v_div FROM public.insc_divisiones
   WHERE torneo = p_torneo AND division = p_division;
  IF NOT FOUND OR NOT v_div.permite_reserva_solo THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'no_permitido',
      'error', 'Esta división no admite reservar cupo sin pareja.');
  END IF;

  -- El rating lo dice la federación, no quien llama
  v_rating := public.insc_rating_federativo(p_member_id);
  IF v_rating IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'sin_rating',
      'error', 'No encontramos tu rating federativo. Comunícate con la FPTM.');
  END IF;
  IF v_div.reserva_rating_min IS NOT NULL AND v_rating < v_div.reserva_rating_min THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'rating_insuficiente',
      'rating', v_rating, 'minimo', v_div.reserva_rating_min,
      'error', 'Reservar cupo en ' || v_div.nombre || ' sin pareja requiere rating '
               || v_div.reserva_rating_min || ' o más. El tuyo es ' || v_rating || '.');
  END IF;

  PERFORM public.insc_equipos_liberar(p_torneo);

  SELECT id, cap_nombre, comp_nombre, estado INTO v_choque
    FROM public.insc_equipos
   WHERE torneo = p_torneo
     AND public.insc_equipo_activo(estado)
     AND p_member_id IN (cap_member_id, comp_member_id)
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'ya_inscrito',
      'error', CASE WHEN v_choque.estado = 'esperando_companero'
                    THEN 'Ya tienes un cupo reservado esperando compañero.'
                    ELSE 'Ya estás inscrito/a en un equipo de este torneo.' END);
  END IF;

  SELECT COUNT(*) INTO v_ocupados FROM public.insc_equipos
   WHERE torneo = p_torneo AND division = p_division
     AND public.insc_equipo_ocupa_cupo(estado);

  -- Un cupo retenido sin pareja no tiene sentido en lista de espera:
  -- si la división está llena, no hay nada que reservar.
  IF v_ocupados >= v_div.max_equipos THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'division_llena',
      'error', v_div.nombre || ' está llena. Inscríbete con un compañero para entrar a la lista de espera.');
  END IF;

  v_expira := NOW() + (public.insc_equipos_reserva_horas() || ' hours')::INTERVAL;

  INSERT INTO public.insc_equipos (
    torneo, division, estado, nombre_equipo, club,
    cap_member_id, cap_nombre, cap_rating, cap_email, cap_tel,
    comp_nombre, costo, reserva_expira
  ) VALUES (
    p_torneo, p_division, 'esperando_companero',
    NULLIF(btrim(COALESCE(p_nombre_equipo, '')), ''),
    NULLIF(btrim(COALESCE(p_club, '')), ''),
    p_member_id, btrim(p_nombre), v_rating,
    NULLIF(btrim(COALESCE(p_email, '')), ''),
    NULLIF(btrim(COALESCE(p_tel, '')), ''),
    NULL, v_div.precio, v_expira
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'estado', 'esperando_companero',
    'division', p_division, 'division_nombre', v_div.nombre,
    'costo', v_div.precio, 'rating', v_rating,
    'rating_min_division', v_div.rating_min,
    'reserva_expira', v_expira,
    'cupos_restantes', v_div.max_equipos - v_ocupados - 1);
END;
$$;


-- ---------------------------------------------------------------------------
-- 5c. NOMBRAR AL COMPAÑERO DE UN CUPO RESERVADO
--     Si la pareja llega al mínimo de la división, el equipo queda normal.
--     Si no llega, va a revisión de la Dirección Técnica — no se baja solo
--     ni se aprueba solo, porque es dinero ya cobrado.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.nombrar_companero(
  p_equipo_id      BIGINT,
  p_torneo         TEXT,
  p_comp_member_id INTEGER,
  p_comp_nombre    TEXT,
  p_comp_invitado  BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_eq        RECORD;
  v_div       RECORD;
  v_norm      TEXT := public.insc_nombre_norm(p_comp_nombre);
  v_rating    INTEGER;
  v_combinado INTEGER;
  v_estado    TEXT;
  v_choque    RECORD;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_equipos:' || p_torneo));

  SELECT * INTO v_eq FROM public.insc_equipos
   WHERE id = p_equipo_id AND torneo = p_torneo;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'no_existe',
      'error', 'No encontramos esa reserva.');
  END IF;
  IF v_eq.estado <> 'esperando_companero' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'estado_invalido',
      'error', 'Esa reserva ya no está esperando compañero.');
  END IF;
  IF v_norm = '' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'incompleto',
      'error', 'Hace falta el nombre del compañero.');
  END IF;
  IF p_comp_member_id IS NOT NULL AND p_comp_member_id = v_eq.cap_member_id THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'mismo_jugador',
      'error', 'El compañero no puede ser tú mismo.');
  END IF;

  SELECT cap_nombre, comp_nombre INTO v_choque FROM public.insc_equipos
   WHERE torneo = p_torneo AND id <> p_equipo_id
     AND public.insc_equipo_activo(estado)
     AND ( (p_comp_member_id IS NOT NULL AND p_comp_member_id IN (cap_member_id, comp_member_id))
        OR (p_comp_member_id IS NULL AND v_norm IN (public.insc_nombre_norm(cap_nombre),
                                                    public.insc_nombre_norm(comp_nombre))) )
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'ya_inscrito',
      'error', btrim(p_comp_nombre) || ' ya está inscrito/a en otro equipo de este torneo.');
  END IF;

  SELECT * INTO v_div FROM public.insc_divisiones
   WHERE torneo = p_torneo AND division = v_eq.division;

  v_rating := CASE WHEN COALESCE(p_comp_invitado, FALSE) THEN NULL
                   ELSE public.insc_rating_federativo(p_comp_member_id) END;

  IF v_rating IS NOT NULL AND v_eq.cap_rating IS NOT NULL THEN
    v_combinado := v_eq.cap_rating + v_rating;
  END IF;

  -- Llega al mínimo de la división → equipo normal. Si no (o si es un
  -- invitado sin rating), lo mira la Dirección Técnica.
  IF v_combinado IS NOT NULL
     AND (v_div.rating_min IS NULL OR v_combinado >= v_div.rating_min)
     AND (v_div.rating_max IS NULL OR v_combinado <= v_div.rating_max) THEN
    v_estado := CASE WHEN v_eq.pagado THEN 'confirmado' ELSE 'reservado' END;
  ELSE
    v_estado := 'revision_tecnica';
  END IF;

  UPDATE public.insc_equipos
     SET comp_member_id   = p_comp_member_id,
         comp_nombre      = btrim(p_comp_nombre),
         comp_rating      = v_rating,
         comp_invitado    = COALESCE(p_comp_invitado, FALSE),
         rating_combinado = v_combinado,
         estado           = v_estado,
         updated_at       = NOW()
   WHERE id = p_equipo_id;

  RETURN jsonb_build_object('ok', true, 'id', p_equipo_id, 'estado', v_estado,
    'rating_combinado', v_combinado,
    'division', v_eq.division, 'division_nombre', v_div.nombre,
    'rating_min_division', v_div.rating_min,
    'requiere_revision', v_estado = 'revision_tecnica');
END;
$$;


-- ---------------------------------------------------------------------------
-- 5d. RESOLUCIÓN DE LA DIRECCIÓN TÉCNICA  (solo admin)
--     'aprobar' deja el equipo en su división aunque no llegue al mínimo.
--     'bajar'   lo manda a la división que le toca por rating combinado y
--               ajusta el costo; si esa división está llena, va a la espera.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolver_revision_tecnica(
  p_equipo_id BIGINT, p_torneo TEXT, p_accion TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_eq       RECORD;
  v_div      RECORD;
  v_ocupados INTEGER;
  v_estado   TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_equipos:' || p_torneo));

  SELECT * INTO v_eq FROM public.insc_equipos
   WHERE id = p_equipo_id AND torneo = p_torneo AND estado = 'revision_tecnica';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ese equipo no está en revisión técnica.');
  END IF;

  IF p_accion = 'aprobar' THEN
    UPDATE public.insc_equipos
       SET estado = CASE WHEN pagado THEN 'confirmado' ELSE 'reservado' END,
           updated_at = NOW()
     WHERE id = p_equipo_id;
    RETURN jsonb_build_object('ok', true, 'accion', 'aprobar', 'division', v_eq.division);
  END IF;

  IF p_accion <> 'bajar' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Acción no reconocida.');
  END IF;

  IF v_eq.rating_combinado IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'Sin rating combinado no se puede calcular la división. Asígnala a mano.');
  END IF;

  SELECT * INTO v_div FROM public.insc_divisiones
   WHERE torneo = p_torneo
     AND (rating_min IS NULL OR v_eq.rating_combinado >= rating_min)
     AND (rating_max IS NULL OR v_eq.rating_combinado <= rating_max)
   ORDER BY orden LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'No hay división para un rating combinado de ' || v_eq.rating_combinado || '.');
  END IF;

  SELECT COUNT(*) INTO v_ocupados FROM public.insc_equipos
   WHERE torneo = p_torneo AND division = v_div.division
     AND id <> p_equipo_id AND public.insc_equipo_ocupa_cupo(estado);

  v_estado := CASE WHEN v_ocupados < v_div.max_equipos
                   THEN CASE WHEN v_eq.pagado THEN 'confirmado' ELSE 'reservado' END
                   ELSE 'lista_espera' END;

  UPDATE public.insc_equipos
     SET division = v_div.division, costo = v_div.precio, estado = v_estado,
         updated_at = NOW()
   WHERE id = p_equipo_id;

  -- El cupo que deja libre en la división de arriba pasa al siguiente
  PERFORM public.insc_equipos_liberar(p_torneo);

  RETURN jsonb_build_object('ok', true, 'accion', 'bajar',
    'division', v_div.division, 'division_nombre', v_div.nombre,
    'costo_nuevo', v_div.precio, 'costo_anterior', v_eq.costo,
    'diferencia', v_eq.costo - v_div.precio, 'estado', v_estado);
END;
$$;


-- ---------------------------------------------------------------------------
-- 5e. LIBERAR UN CUPO Y DEJAR EL DINERO COMO CRÉDITO  (solo admin)
--     Para el que compró cupo y nunca nombró compañero: el cupo vuelve al
--     torneo y lo pagado queda a favor del jugador para el próximo evento.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.liberar_cupo_con_credito(
  p_equipo_id BIGINT, p_torneo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_monto NUMERIC(8,2);
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_equipos:' || p_torneo));

  UPDATE public.insc_equipos
     SET estado = 'credito', credito = COALESCE(monto_pagado, 0),
         reserva_expira = NULL, updated_at = NOW()
   WHERE id = p_equipo_id AND torneo = p_torneo
     AND public.insc_equipo_activo(estado)
  RETURNING credito INTO v_monto;

  IF v_monto IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'No encontramos ese equipo activo.');
  END IF;

  PERFORM public.insc_equipos_liberar(p_torneo);
  RETURN jsonb_build_object('ok', true, 'credito', v_monto);
END;
$$;


-- ---------------------------------------------------------------------------
-- 5f. EDITAR UN EQUIPO  (solo admin)
--
--  Cambiar el nombre del equipo o el club es texto. Cambiar un JUGADOR no:
--  el rating está congelado en la fila, así que al sustituir a alguien cambia
--  el rating combinado, y con él la división y el costo. Por eso esta función
--  repite las mismas comprobaciones que la inscripción en vez de dejar que el
--  panel escriba columnas a mano.
--
--  p_division manda sobre el cálculo: NULL recalcula por rating combinado, y
--  un valor explícito es la Dirección Técnica diciendo "este equipo se queda
--  aquí" — su potestad, no un error a corregir.
--
--  Deja el compañero vacío (p_comp_nombre NULL) y el equipo vuelve a esperar
--  pareja, conservando su cupo.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.editar_equipo(
  p_equipo_id      BIGINT,
  p_torneo         TEXT,
  p_cap_member_id  INTEGER,
  p_cap_nombre     TEXT,
  p_comp_member_id INTEGER  DEFAULT NULL,
  p_comp_nombre    TEXT     DEFAULT NULL,
  p_cap_invitado   BOOLEAN  DEFAULT FALSE,
  p_comp_invitado  BOOLEAN  DEFAULT FALSE,
  p_nombre_equipo  TEXT     DEFAULT NULL,
  p_club           TEXT     DEFAULT NULL,
  p_email          TEXT     DEFAULT NULL,
  p_tel            TEXT     DEFAULT NULL,
  p_division       TEXT     DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_eq        RECORD;
  v_cap_norm  TEXT := public.insc_nombre_norm(p_cap_nombre);
  v_comp_norm TEXT := public.insc_nombre_norm(p_comp_nombre);
  v_cap_rat   INTEGER;
  v_comp_rat  INTEGER;
  v_combinado INTEGER;
  v_div       RECORD;
  v_ocupados  INTEGER;
  v_estado    TEXT;
  v_costo     NUMERIC(8,2) := 0;
  v_pagado    NUMERIC(8,2);
  v_choque    RECORD;
  v_cambios   TEXT := '';
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_equipos:' || p_torneo));

  SELECT * INTO v_eq FROM public.insc_equipos
   WHERE id = p_equipo_id AND torneo = p_torneo;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'No encontramos ese equipo.');
  END IF;

  IF v_cap_norm = '' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'incompleto',
      'error', 'El equipo necesita al menos al jugador 1.');
  END IF;

  IF (p_cap_member_id IS NOT NULL AND p_cap_member_id = p_comp_member_id)
     OR (p_cap_member_id IS NULL AND p_comp_member_id IS NULL
         AND v_comp_norm <> '' AND v_cap_norm = v_comp_norm) THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'mismo_jugador',
      'error', 'Los dos jugadores no pueden ser la misma persona.');
  END IF;

  -- Un jugador, un equipo — mirando todos los demás equipos vivos del torneo
  SELECT id, cap_nombre, comp_nombre INTO v_choque
    FROM public.insc_equipos
   WHERE torneo = p_torneo AND id <> p_equipo_id
     AND public.insc_equipo_activo(estado)
     AND (
          (p_cap_member_id  IS NOT NULL AND p_cap_member_id  IN (cap_member_id, comp_member_id))
       OR (p_comp_member_id IS NOT NULL AND p_comp_member_id IN (cap_member_id, comp_member_id))
       OR (p_cap_member_id  IS NULL AND v_cap_norm  IN (public.insc_nombre_norm(cap_nombre),
                                                        public.insc_nombre_norm(comp_nombre)))
       OR (p_comp_member_id IS NULL AND v_comp_norm <> ''
           AND v_comp_norm IN (public.insc_nombre_norm(cap_nombre),
                               public.insc_nombre_norm(comp_nombre)))
     )
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'ya_inscrito',
      'error', 'Uno de esos jugadores ya está en el equipo '
               || v_choque.cap_nombre || ' / ' || COALESCE(v_choque.comp_nombre, '(por definir)') || '.');
  END IF;

  -- El rating lo pone la federación, igual que en la inscripción
  v_cap_rat  := CASE WHEN COALESCE(p_cap_invitado, FALSE)  THEN NULL
                     ELSE public.insc_rating_federativo(p_cap_member_id) END;
  v_comp_rat := CASE WHEN COALESCE(p_comp_invitado, FALSE) OR v_comp_norm = '' THEN NULL
                     ELSE public.insc_rating_federativo(p_comp_member_id) END;
  IF v_cap_rat IS NOT NULL AND v_comp_rat IS NOT NULL THEN
    v_combinado := v_cap_rat + v_comp_rat;
  END IF;

  -- División: la impuesta por el admin, o la que toca por rating
  IF p_division IS NOT NULL THEN
    SELECT * INTO v_div FROM public.insc_divisiones
     WHERE torneo = p_torneo AND division = p_division;
  ELSIF v_combinado IS NOT NULL THEN
    SELECT * INTO v_div FROM public.insc_divisiones
     WHERE torneo = p_torneo
       AND (rating_min IS NULL OR v_combinado >= rating_min)
       AND (rating_max IS NULL OR v_combinado <= rating_max)
     ORDER BY orden LIMIT 1;
  ELSIF v_eq.division IS NOT NULL THEN
    SELECT * INTO v_div FROM public.insc_divisiones
     WHERE torneo = p_torneo AND division = v_eq.division;
  END IF;

  IF v_div.division IS NOT NULL THEN
    v_costo := v_div.precio;
  END IF;

  -- Estado resultante
  IF v_comp_norm = '' THEN
    v_estado := 'esperando_companero';
  ELSIF v_div.division IS NULL THEN
    v_estado := 'pendiente_division';
  ELSE
    -- Si el equipo se muda a una división llena, entra por la lista de espera
    IF v_div.division IS DISTINCT FROM v_eq.division THEN
      SELECT COUNT(*) INTO v_ocupados FROM public.insc_equipos
       WHERE torneo = p_torneo AND division = v_div.division
         AND id <> p_equipo_id AND public.insc_equipo_ocupa_cupo(estado);
      IF v_ocupados >= v_div.max_equipos THEN
        v_estado := 'lista_espera';
      END IF;
    END IF;
    IF v_estado IS NULL THEN
      v_estado := CASE WHEN COALESCE(v_eq.monto_pagado, 0) >= v_costo AND v_costo > 0
                       THEN 'confirmado' ELSE 'reservado' END;
    END IF;
  END IF;

  v_pagado := COALESCE(v_eq.monto_pagado, 0);

  -- Rastro de lo que cambió: hay dinero de por medio
  IF v_eq.cap_nombre  IS DISTINCT FROM btrim(p_cap_nombre) THEN
    v_cambios := v_cambios || 'jugador 1: ' || v_eq.cap_nombre || ' → ' || btrim(p_cap_nombre) || '; ';
  END IF;
  IF COALESCE(v_eq.comp_nombre,'') IS DISTINCT FROM COALESCE(btrim(p_comp_nombre),'') THEN
    v_cambios := v_cambios || 'jugador 2: ' || COALESCE(v_eq.comp_nombre,'(vacío)')
              || ' → ' || COALESCE(NULLIF(btrim(p_comp_nombre),''),'(vacío)') || '; ';
  END IF;
  IF v_eq.division IS DISTINCT FROM v_div.division THEN
    v_cambios := v_cambios || 'división: ' || COALESCE(v_eq.division,'—')
              || ' → ' || COALESCE(v_div.division,'—')
              || ' ($' || v_eq.costo || ' → $' || v_costo || '); ';
  END IF;

  UPDATE public.insc_equipos
     SET nombre_equipo    = NULLIF(btrim(COALESCE(p_nombre_equipo, '')), ''),
         club             = NULLIF(btrim(COALESCE(p_club, '')), ''),
         cap_member_id    = p_cap_member_id,
         cap_nombre       = btrim(p_cap_nombre),
         cap_rating       = v_cap_rat,
         cap_invitado     = COALESCE(p_cap_invitado, FALSE),
         cap_email        = COALESCE(NULLIF(btrim(COALESCE(p_email, '')), ''), cap_email),
         cap_tel          = COALESCE(NULLIF(btrim(COALESCE(p_tel, '')), ''), cap_tel),
         comp_member_id   = CASE WHEN v_comp_norm = '' THEN NULL ELSE p_comp_member_id END,
         comp_nombre      = NULLIF(btrim(COALESCE(p_comp_nombre, '')), ''),
         comp_rating      = v_comp_rat,
         comp_invitado    = COALESCE(p_comp_invitado, FALSE) AND v_comp_norm <> '',
         rating_combinado = v_combinado,
         division         = v_div.division,
         costo            = v_costo,
         estado           = v_estado,
         pagado           = v_pagado >= v_costo AND v_costo > 0,
         notas            = CASE WHEN v_cambios = '' THEN notas
                                 ELSE COALESCE(notas || ' | ', '') || 'Editado: ' || v_cambios END,
         updated_at       = NOW()
   WHERE id = p_equipo_id;

  -- El cupo que suelte al mudarse pasa a quien esté esperando
  PERFORM public.insc_equipos_liberar(p_torneo);

  RETURN jsonb_build_object(
    'ok', true, 'id', p_equipo_id, 'estado', v_estado,
    'division', v_div.division, 'division_nombre', v_div.nombre,
    'rating_combinado', v_combinado,
    'costo', v_costo, 'costo_anterior', v_eq.costo,
    'diferencia', v_eq.costo - v_costo,
    'monto_pagado', v_pagado,
    'saldo', GREATEST(0, v_costo - v_pagado),
    'division_cambio', v_eq.division IS DISTINCT FROM v_div.division,
    'cambios', NULLIF(v_cambios, ''));
END;
$$;


-- ---------------------------------------------------------------------------
-- 6. VISTAS PÚBLICAS
--    El portal necesita mostrar equipos y cupos sin exponer email, teléfono,
--    referencia de pago ni montos. La tabla base queda cerrada al público y
--    estas vistas son la única ventana: no es disciplina del cliente, es que
--    las columnas sensibles literalmente no existen aquí.
-- ---------------------------------------------------------------------------
-- DROP antes de CREATE: la vista gana columnas en medio y CREATE OR REPLACE
-- solo sabe añadirlas al final.
DROP VIEW IF EXISTS public.insc_equipos_publico;
CREATE VIEW public.insc_equipos_publico
WITH (security_invoker = off) AS
SELECT
  e.id, e.torneo, e.division, e.estado,
  e.nombre_equipo, e.club,
  -- Los member_id ya son públicos en el ranking; hacen falta aquí para saber
  -- si quien llena el formulario es el dueño de un cupo esperando compañero.
  e.cap_member_id,  e.cap_nombre,  e.cap_rating,
  e.comp_member_id, e.comp_nombre, e.comp_rating,
  e.rating_combinado,
  e.created_at
FROM public.insc_equipos e
WHERE public.insc_equipo_activo(e.estado);

CREATE OR REPLACE VIEW public.insc_equipos_cupos
WITH (security_invoker = off) AS
SELECT
  d.torneo, d.division, d.nombre, d.rating_min, d.rating_max,
  d.precio, d.max_equipos, d.orden,
  COUNT(*) FILTER (WHERE public.insc_equipo_ocupa_cupo(e.estado))       AS ocupados,
  GREATEST(d.max_equipos
    - COUNT(*) FILTER (WHERE public.insc_equipo_ocupa_cupo(e.estado)), 0) AS disponibles,
  COUNT(*) FILTER (WHERE e.estado = 'lista_espera')                     AS en_espera,
  COUNT(*) FILTER (WHERE e.estado = 'confirmado')                       AS confirmados,
  COUNT(*) FILTER (WHERE e.estado = 'esperando_companero')               AS esperando_companero,
  COUNT(*) FILTER (WHERE e.estado = 'revision_tecnica')                  AS en_revision
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
GRANT EXECUTE ON FUNCTION public.reservar_cupo_solo(
  TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nombrar_companero(
  BIGINT, TEXT, INTEGER, TEXT, BOOLEAN)                      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolver_revision_tecnica(BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.editar_equipo(
  BIGINT, TEXT, INTEGER, TEXT, INTEGER, TEXT, BOOLEAN, BOOLEAN,
  TEXT, TEXT, TEXT, TEXT, TEXT)                              TO authenticated;
GRANT EXECUTE ON FUNCTION public.liberar_cupo_con_credito(BIGINT, TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.insc_rating_federativo(INTEGER)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.insc_equipo_ocupa_cupo(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insc_equipo_activo(TEXT)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insc_equipos_reserva_horas()    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insc_nombre_norm(TEXT)          TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 9. VERIFICACIÓN
-- ---------------------------------------------------------------------------
SELECT division, nombre, precio, max_equipos, ocupados, disponibles, en_espera
  FROM public.insc_equipos_cupos
 WHERE torneo = 'Copa Olímpica 2026'
 ORDER BY orden;
