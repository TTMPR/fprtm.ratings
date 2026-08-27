-- ============================================================================
-- 060 · Copa Olímpica — equipos, divisiones y Busco Compañero
--
-- Depende de: 010 ("Base de Datos"), 030 (insc_registro), 050 (app_settings).
--
-- Origen: sql/create_insc_equipos.sql + sql/create_busca_companero.sql
-- Copiado literal: el módulo original ya es idempotente, autocontenido y
-- ordenado. Reescribirlo introduciría deriva respecto a producción.
-- ============================================================================

-- ────────── sql/create_insc_equipos.sql ──────────
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
--    expirado             venció la reserva sin pago; el cupo se liberó
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
     AND estado IN ('reservado', 'esperando_companero')
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

-- ────────── sql/create_busca_companero.sql ──────────
-- ============================================================================
--  FPTM — Tablón "Busco Compañero"
--  Ejecutar en: Supabase → SQL Editor  (seguro de re-ejecutar)
--
--  Para torneos por equipos o de dobles: quien no tiene pareja publica que
--  busca, y los demás lo ven. Se guarda por torneo, así que sirve para la
--  Copa Olímpica ahora y para cualquier evento futuro sin tocar el esquema.
--
--  Decisión de la federación: el contacto es PÚBLICO y opcional. Quien
--  publica escoge si pone WhatsApp, email o nada. Queda visible para
--  cualquiera que abra la página — así es como funciona un tablón.
--
--  La excepción son los menores. Un menor de 18 no publica contacto: su
--  anuncio sale, pero quien quiera contactarlo pasa por la FPTM. Y esa
--  decisión NO la toma el navegador: se calcula aquí, contra la fecha de
--  nacimiento de "Base de Datos". Si el formulario mintiera o fallara, el
--  teléfono del menor seguiría sin publicarse.
--
--  Requiere sql/create_insc_equipos.sql: la vista pública esconde a quien ya
--  aparece en un equipo inscrito, y eso se consulta contra insc_equipos.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. HELPER: fecha de nacimiento → DATE
--    "Date of Birth" es TEXT con tres formatos históricos mezclados. Esta
--    función replica lo justo de _parseDOBStr() del index.html.
--
--    Sí, sql/create_api_publica.sql tiene una versión más completa
--    (fprtm_parse_fecha). No se reutiliza a propósito: ese script es para la
--    página oficial y puede no haberse corrido en esta base. Que el tablón
--    dependa de él sería que un menor publique su teléfono porque faltaba
--    correr un archivo que no tiene nada que ver.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insc_dob_a_fecha(raw TEXT)
RETURNS DATE
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE
  t TEXT; m TEXT[]; yy INT;
  meses CONSTANT TEXT[] := ARRAY['jan','feb','mar','apr','may','jun',
                                 'jul','aug','sep','oct','nov','dec'];
BEGIN
  IF raw IS NULL THEN RETURN NULL; END IF;
  t := btrim(raw);
  IF t = '' THEN RETURN NULL; END IF;

  -- ISO: 2001-11-25
  m := regexp_match(t, '^(\d{4})-(\d{1,2})-(\d{1,2})$');
  IF m IS NOT NULL THEN
    BEGIN RETURN make_date(m[1]::INT, m[2]::INT, m[3]::INT);
    EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  END IF;

  -- D-Mon-YY(YY): 25-Nov-01
  m := regexp_match(lower(t), '^(\d{1,2})-([a-z]{3})-(\d{2,4})$');
  IF m IS NOT NULL THEN
    yy := m[3]::INT;
    IF length(m[3]) = 2 THEN yy := CASE WHEN yy < 30 THEN 2000 + yy ELSE 1900 + yy END; END IF;
    BEGIN RETURN make_date(yy, array_position(meses, m[2]), m[1]::INT);
    EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  END IF;

  -- M/D/YY(YY): 11/25/2001
  m := regexp_match(t, '^(\d{1,2})/(\d{1,2})/(\d{2,4})$');
  IF m IS NOT NULL THEN
    yy := m[3]::INT;
    IF length(m[3]) = 2 THEN yy := CASE WHEN yy < 30 THEN 2000 + yy ELSE 1900 + yy END; END IF;
    BEGIN RETURN make_date(yy, m[1]::INT, m[2]::INT);
    EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  END IF;

  RETURN NULL;
END;
$$;

-- ¿Es menor de 18 hoy? NULL cuando no hay fecha utilizable en la base.
CREATE OR REPLACE FUNCTION public.insc_es_menor(p_member_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_dob DATE;
BEGIN
  IF p_member_id IS NULL THEN RETURN NULL; END IF;
  SELECT public.insc_dob_a_fecha(b."Date of Birth") INTO v_dob
    FROM public."Base de Datos" b WHERE b."Member ID" = p_member_id;
  IF v_dob IS NULL THEN RETURN NULL; END IF;
  RETURN v_dob > (CURRENT_DATE - INTERVAL '18 years');
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;   -- columna o tabla distinta de lo esperado: decide quien llama
END;
$$;


-- ---------------------------------------------------------------------------
-- 2. TABLA
--    estado: activo | emparejado | retirado | oculto  (oculto = lo bajó el admin)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.insc_busca_companero (
  id             BIGSERIAL PRIMARY KEY,
  torneo         TEXT NOT NULL,
  member_id      INTEGER,
  nombre         TEXT NOT NULL,
  nombre_norm    TEXT NOT NULL,
  rating         INTEGER,
  club           TEXT,
  nota           TEXT,
  contacto_tipo  TEXT NOT NULL DEFAULT 'ninguno',
  contacto_valor TEXT,
  es_menor       BOOLEAN NOT NULL DEFAULT FALSE,
  estado         TEXT NOT NULL DEFAULT 'activo',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT insc_busca_estado_chk   CHECK (estado IN ('activo','emparejado','retirado','oculto')),
  CONSTRAINT insc_busca_contacto_chk CHECK (contacto_tipo IN ('whatsapp','email','ninguno'))
);

-- Un anuncio activo por persona y torneo. Quien se retira puede volver a publicar.
CREATE UNIQUE INDEX IF NOT EXISTS insc_busca_uniq_member
  ON public.insc_busca_companero (torneo, member_id)
  WHERE member_id IS NOT NULL AND estado = 'activo';
CREATE UNIQUE INDEX IF NOT EXISTS insc_busca_uniq_invitado
  ON public.insc_busca_companero (torneo, nombre_norm)
  WHERE member_id IS NULL AND estado = 'activo';
CREATE INDEX IF NOT EXISTS insc_busca_torneo_idx
  ON public.insc_busca_companero (torneo, estado);

CREATE OR REPLACE FUNCTION public.insc_busca_touch()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN NEW.updated_at := NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS insc_busca_touch_trg ON public.insc_busca_companero;
CREATE TRIGGER insc_busca_touch_trg
  BEFORE UPDATE ON public.insc_busca_companero
  FOR EACH ROW EXECUTE FUNCTION public.insc_busca_touch();


-- ---------------------------------------------------------------------------
-- 3. VISTA PÚBLICA
--    Dos cosas pasan aquí y no en el navegador:
--      · quien ya está en un equipo inscrito desaparece del tablón — nadie
--        tiene que acordarse de retirar su anuncio;
--      · el contacto de un menor no sale, pase lo que pase.
-- ---------------------------------------------------------------------------
--  Un matiz que importa: quien COMPRÓ un cupo sin pareja (esperando_companero)
--  no desaparece del tablón — es justo quien más necesita que lo vean. Su
--  anuncio además muestra qué cupo trae ya pagado, que es el mejor argumento
--  posible para que alguien se le una.
-- DROP antes de CREATE: la vista ganó columnas y CREATE OR REPLACE no puede
-- reordenar ni insertar columnas en medio.
DROP VIEW IF EXISTS public.insc_busca_companero_publico;
CREATE VIEW public.insc_busca_companero_publico
WITH (security_invoker = off) AS
SELECT
  b.id, b.torneo, b.member_id, b.nombre, b.rating, b.club, b.nota,
  b.es_menor,
  CASE WHEN b.es_menor THEN 'ninguno' ELSE b.contacto_tipo  END AS contacto_tipo,
  CASE WHEN b.es_menor THEN NULL      ELSE b.contacto_valor END AS contacto_valor,
  cupo.id       AS cupo_equipo_id,
  cupo.division AS cupo_division,
  d.nombre      AS cupo_division_nombre,
  b.created_at
FROM public.insc_busca_companero b
LEFT JOIN LATERAL (
  SELECT e.id, e.division FROM public.insc_equipos e
   WHERE e.torneo = b.torneo AND e.estado = 'esperando_companero'
     AND b.member_id IS NOT NULL AND e.cap_member_id = b.member_id
   LIMIT 1
) cupo ON TRUE
LEFT JOIN public.insc_divisiones d
       ON d.torneo = b.torneo AND d.division = cupo.division
WHERE b.estado = 'activo'
  AND NOT EXISTS (
    SELECT 1 FROM public.insc_equipos e
     WHERE e.torneo = b.torneo
       AND public.insc_equipo_activo(e.estado)
       AND e.estado <> 'esperando_companero'
       AND ( (b.member_id IS NOT NULL AND b.member_id IN (e.cap_member_id, e.comp_member_id))
          OR (b.member_id IS NULL AND b.nombre_norm IN (public.insc_nombre_norm(e.cap_nombre),
                                                        public.insc_nombre_norm(e.comp_nombre))) )
  );


-- ---------------------------------------------------------------------------
-- 4. PUBLICAR ANUNCIO
--
--  p_adulto_declarado solo se usa cuando la base no tiene fecha de nacimiento
--  utilizable. Con fecha, manda la fecha. Sin fecha y sin declaración, el
--  contacto no se publica: preferimos un anuncio sin teléfono a publicar el
--  de un menor por no saberlo.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publicar_busca_companero(
  p_torneo           TEXT,
  p_member_id        INTEGER,
  p_nombre           TEXT,
  p_rating           INTEGER  DEFAULT NULL,
  p_club             TEXT     DEFAULT NULL,
  p_nota             TEXT     DEFAULT NULL,
  p_contacto_tipo    TEXT     DEFAULT 'ninguno',
  p_contacto_valor   TEXT     DEFAULT NULL,
  p_adulto_declarado BOOLEAN  DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_norm    TEXT := public.insc_nombre_norm(p_nombre);
  v_abierto TEXT;
  v_cierre  TEXT;
  v_menor   BOOLEAN;
  v_tipo    TEXT := lower(COALESCE(btrim(p_contacto_tipo), 'ninguno'));
  v_valor   TEXT := NULLIF(btrim(COALESCE(p_contacto_valor, '')), '');
  v_equipo  RECORD;
  v_id      BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_busca:' || p_torneo));

  IF v_norm = '' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'incompleto',
      'error', 'Hace falta tu nombre.');
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

  -- Quien ya tiene equipo no busca compañero. Excepción: quien compró un cupo
  -- y aún no tiene con quién jugar — ese sí, y con más razón que nadie.
  SELECT cap_nombre, comp_nombre INTO v_equipo
    FROM public.insc_equipos
   WHERE torneo = p_torneo
     AND public.insc_equipo_activo(estado)
     AND estado <> 'esperando_companero'
     AND ( (p_member_id IS NOT NULL AND p_member_id IN (cap_member_id, comp_member_id))
        OR (p_member_id IS NULL AND v_norm IN (public.insc_nombre_norm(cap_nombre),
                                               public.insc_nombre_norm(comp_nombre))) )
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'ya_tiene_equipo',
      'equipo', v_equipo.cap_nombre || ' / ' || v_equipo.comp_nombre,
      'error', 'Ya estás inscrito/a en el equipo ' || v_equipo.cap_nombre || ' / ' || v_equipo.comp_nombre || '.');
  END IF;

  -- Edad: manda la base; la declaración solo cubre el hueco
  v_menor := public.insc_es_menor(p_member_id);
  IF v_menor IS NULL THEN
    v_menor := NOT COALESCE(p_adulto_declarado, FALSE);
  END IF;

  IF v_tipo NOT IN ('whatsapp','email') OR v_valor IS NULL THEN
    v_tipo := 'ninguno'; v_valor := NULL;
  END IF;
  IF v_menor THEN
    v_tipo := 'ninguno'; v_valor := NULL;
  END IF;

  -- Republicar reemplaza el anuncio anterior en vez de duplicarlo
  UPDATE public.insc_busca_companero
     SET estado = 'retirado'
   WHERE torneo = p_torneo AND estado = 'activo'
     AND ( (p_member_id IS NOT NULL AND member_id = p_member_id)
        OR (p_member_id IS NULL AND member_id IS NULL AND nombre_norm = v_norm) );

  INSERT INTO public.insc_busca_companero
    (torneo, member_id, nombre, nombre_norm, rating, club, nota,
     contacto_tipo, contacto_valor, es_menor)
  VALUES
    (p_torneo, p_member_id, btrim(p_nombre), v_norm, p_rating,
     NULLIF(btrim(COALESCE(p_club, '')), ''),
     NULLIF(btrim(COALESCE(p_nota, '')), ''),
     v_tipo, v_valor, v_menor)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id,
    'es_menor', v_menor, 'contacto_publicado', v_tipo <> 'ninguno');
END;
$$;


-- ---------------------------------------------------------------------------
-- 5. RETIRAR ANUNCIO ("ya encontré compañero")
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retirar_busca_companero(p_id BIGINT, p_torneo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INTEGER;
BEGIN
  UPDATE public.insc_busca_companero
     SET estado = 'emparejado'
   WHERE id = p_id AND torneo = p_torneo AND estado = 'activo';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', v_n > 0);
END;
$$;


-- ---------------------------------------------------------------------------
-- 6. PERMISOS
-- ---------------------------------------------------------------------------
ALTER TABLE public.insc_busca_companero ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_all_insc_busca ON public.insc_busca_companero;
CREATE POLICY admin_all_insc_busca
  ON public.insc_busca_companero FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

REVOKE ALL    ON public.insc_busca_companero FROM anon;
GRANT  ALL    ON public.insc_busca_companero TO   authenticated;
GRANT  SELECT ON public.insc_busca_companero_publico TO anon, authenticated;
GRANT  USAGE, SELECT ON SEQUENCE public.insc_busca_companero_id_seq TO authenticated;

GRANT EXECUTE ON FUNCTION public.publicar_busca_companero(
  TEXT, INTEGER, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.retirar_busca_companero(BIGINT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insc_es_menor(INTEGER)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.insc_dob_a_fecha(TEXT)   TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 7. VERIFICACIÓN
-- ---------------------------------------------------------------------------
SELECT nombre, rating, contacto_tipo, es_menor
  FROM public.insc_busca_companero_publico
 WHERE torneo = 'Copa Olímpica 2026'
 ORDER BY rating DESC NULLS LAST;
