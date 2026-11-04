-- =============================================================================
--  Campeonatos Nacionales 2026 — inscripciones individuales y de dobles
--  12, 13, 19 y 20 de diciembre de 2026 · Albergue Olímpico, Salinas
--
--  Correr UNA vez en el SQL Editor de Supabase (es idempotente: se puede volver
--  a correr sin perder inscripciones). Guía operativa: docs/NACIONALES_2026.md
--
--  Reglas de seguridad que respeta (sql/security/README.md):
--    · Ninguna función SECURITY DEFINER vive en el esquema public. Las que
--      necesitan leer "Base de Datos" viven en internal_security y el navegador
--      llega a ellas por envolturas SECURITY INVOKER en public.
--    · El navegador nunca escribe en las tablas: todo pasa por funciones que
--      validan identidad (Member ID + fecha de nacimiento), membresía, reglas
--      del reglamento y calculan el total en el servidor.
--    · Ninguna tabla nueva es legible por anon, salvo el catálogo de eventos.
--    · El pago lo aprueba solo el administrador (mismo UID que admin.html).
--
--  Al terminar, correr sql/security/verify_access_controls_20261020.sql.
-- =============================================================================

BEGIN;

-- ── 0. Requisitos ──────────────────────────────────────────────────────────
DO $req$
BEGIN
  IF to_regnamespace('internal_security') IS NULL THEN
    RAISE EXCEPTION 'Falta el esquema internal_security (migraciones de seguridad del 20-oct-2026).';
  END IF;
  IF NOT has_schema_privilege('anon', 'internal_security', 'USAGE') THEN
    RAISE EXCEPTION 'anon no tiene USAGE en internal_security; las vistas públicas existentes tampoco funcionarían. Revisa antes de seguir.';
  END IF;
  IF to_regprocedure('public.fprtm_parse_fecha(text)') IS NULL THEN
    RAISE EXCEPTION 'Falta public.fprtm_parse_fecha(text) (sql/schema/080_views.sql).';
  END IF;
  IF to_regclass('public.app_settings') IS NULL THEN
    RAISE EXCEPTION 'Falta public.app_settings (create_app_settings.sql).';
  END IF;
END $req$;


-- ── 1. Catálogo de eventos ─────────────────────────────────────────────────
-- Espejo del documento "Itinerario de Eventos y Premiación". La página lo
-- tiene también en código para pintar; quien decide es esta tabla.
CREATE TABLE IF NOT EXISTS public.nac_eventos (
  codigo        TEXT PRIMARY KEY,
  nombre        TEXT NOT NULL,
  fecha         DATE NOT NULL,
  hora          TIME NOT NULL,
  area          TEXT NOT NULL,
  tipo          TEXT NOT NULL CHECK (tipo IN ('edad','rating','abierto','senior','dobles')),
  sexo          TEXT CHECK (sexo IN ('M','F','X')),   -- X = mixto (dobles mixtos)
  edad_max      INT,
  edad_min      INT,
  rating_max    INT,
  precio        NUMERIC(6,2) NOT NULL,                -- en dobles: por pareja
  premios       TEXT,
  orden         INT NOT NULL,
  stadium_slug  TEXT                                  -- se llena cuando exista el torneo en Stadium
);

INSERT INTO public.nac_eventos (codigo,nombre,fecha,hora,area,tipo,sexo,edad_max,edad_min,rating_max,precio,premios,orden) VALUES
 ('u9f',  '9 años o menos Femenino',        '2026-12-12','09:00','Pabellón',   'edad',   'F', 9,  NULL,NULL,20,'Trofeo 1°–4° · Medalla 5°–8°', 1),
 ('u9m',  '9 años o menos Masculino',       '2026-12-12','09:00','Pabellón',   'edad',   'M', 9,  NULL,NULL,20,'Trofeo 1°–4° · Medalla 5°–8°', 2),
 ('u13f', '13 años o menos Femenino',       '2026-12-12','09:00','Pabellón',   'edad',   'F', 13, NULL,NULL,20,'$45 · $30 · $25 (x2)', 3),
 ('u13m', '13 años o menos Masculino',      '2026-12-12','09:00','Pabellón',   'edad',   'M', 13, NULL,NULL,20,'$45 · $30 · $25 (x2)', 4),
 ('u15f', '15 años o menos Femenino',       '2026-12-12','09:00','Pabellón',   'edad',   'F', 15, NULL,NULL,20,'$55 · $30 · $25 (x2)', 5),
 ('u15m', '15 años o menos Masculino',      '2026-12-12','09:00','Pabellón',   'edad',   'M', 15, NULL,NULL,20,'$55 · $30 · $25 (x2)', 6),
 ('r1900','Rating 1900 o menos',            '2026-12-12','13:00','Pabellón',   'rating', NULL,NULL,NULL,1900,20,'$100 · $75 · $50 (x2)', 7),
 ('r1800','Rating 1800 o menos',            '2026-12-13','09:00','Pabellón',   'rating', NULL,NULL,NULL,1800,20,'$90 · $65 · $45 (x2)', 8),
 ('u19f', '19 años o menos Femenino',       '2026-12-13','13:00','Pabellón',   'edad',   'F', 19, NULL,NULL,20,'$85 · $75 · $65 (x2)', 9),
 ('u19m', '19 años o menos Masculino',      '2026-12-13','13:00','Pabellón',   'edad',   'M', 19, NULL,NULL,20,'$85 · $75 · $65 (x2)', 10),
 ('u11f', '11 años o menos Femenino',       '2026-12-13','13:00','Pabellón',   'edad',   'F', 11, NULL,NULL,20,'$35 · $30 · $25 (x2)', 11),
 ('u11m', '11 años o menos Masculino',      '2026-12-13','13:00','Pabellón',   'edad',   'M', 11, NULL,NULL,20,'$35 · $30 · $25 (x2)', 12),
 ('abm',  'Individual Abierto Masculino',   '2026-12-19','09:00','Pabellón',   'abierto','M', NULL,NULL,NULL,25,'$600 · $300 · $150 (x2)', 13),
 ('abf',  'Individual Abierto Femenino',    '2026-12-19','09:00','Pabellón',   'abierto','F', NULL,NULL,NULL,25,'$600 · $300 · $150 (x2)', 14),
 ('r1700','Rating 1700 o menos',            '2026-12-19','09:00','Polivalente','rating', NULL,NULL,NULL,1700,20,'$80 · $60 · $40 (x2)', 15),
 ('r1500','Rating 1500 o menos',            '2026-12-19','13:00','Polivalente','rating', NULL,NULL,NULL,1500,20,'$60 · $40 · $30 (x2)', 16),
 ('dm',   'Dobles Masculino',               '2026-12-20','09:00','Pabellón',   'dobles', 'M', NULL,NULL,NULL,40,'$150 · $80 por pareja', 17),
 ('df',   'Dobles Femenino',                '2026-12-20','09:00','Pabellón',   'dobles', 'F', NULL,NULL,NULL,40,'$150 · $80 por pareja', 18),
 ('r1600','Rating 1600 o menos',            '2026-12-20','09:00','Polivalente','rating', NULL,NULL,NULL,1600,20,'$70 · $50 · $35 (x2)', 19),
 ('dx',   'Dobles Mixtos',                  '2026-12-20','13:00','Pabellón',   'dobles', 'X', NULL,NULL,NULL,40,'$150 · $80 por pareja', 20),
 ('sen',  'Seniors: 40 años o más (Mixto)', '2026-12-20','13:00','Polivalente','senior', NULL,NULL,40, NULL,20,'$50 · $40 · $30 (x2)', 21),
 ('u7',   '7 años o menos Abierto',         '2026-12-20','13:00','Polivalente','edad',   NULL,7,  NULL,NULL,11,'Trofeo 1°–4° · Medalla 5°–8°', 22)
ON CONFLICT (codigo) DO UPDATE SET
  nombre=EXCLUDED.nombre, fecha=EXCLUDED.fecha, hora=EXCLUDED.hora, area=EXCLUDED.area,
  tipo=EXCLUDED.tipo, sexo=EXCLUDED.sexo, edad_max=EXCLUDED.edad_max, edad_min=EXCLUDED.edad_min,
  rating_max=EXCLUDED.rating_max, precio=EXCLUDED.precio, premios=EXCLUDED.premios, orden=EXCLUDED.orden;
  -- stadium_slug no se toca: lo llena el admin desde nacionales-admin.html

ALTER TABLE public.nac_eventos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS nac_eventos_lectura ON public.nac_eventos;
CREATE POLICY nac_eventos_lectura ON public.nac_eventos FOR SELECT TO anon, authenticated USING (true);
REVOKE ALL ON public.nac_eventos FROM anon, authenticated;
GRANT SELECT ON public.nac_eventos TO anon, authenticated;


-- ── 2. Inscripciones ───────────────────────────────────────────────────────
-- Una inscripción = un envío del formulario = un pago. Un jugador puede hacer
-- más de una (por ejemplo, añadir Dobles después); cada una se valida contra
-- todo lo que ya tiene activo.
CREATE TABLE IF NOT EXISTS public.nac_inscripciones (
  id                      BIGSERIAL PRIMARY KEY,
  member_id               BIGINT NOT NULL,          -- quien inscribe (y paga)
  nombre                  TEXT NOT NULL,
  total                   NUMERIC(8,2) NOT NULL,
  estado                  TEXT NOT NULL DEFAULT 'pendiente'
                            CHECK (estado IN ('pendiente','aprobada','cancelada')),
  reglamento_version      TEXT NOT NULL,
  reglamento_aceptado_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  aprobada_at             TIMESTAMPTZ,
  aprobada_por            UUID,
  cancelada_at            TIMESTAMPTZ,
  nota_admin              TEXT
);
CREATE INDEX IF NOT EXISTS nac_inscripciones_member_idx ON public.nac_inscripciones (member_id);
CREATE INDEX IF NOT EXISTS nac_inscripciones_estado_idx ON public.nac_inscripciones (estado);

-- Una fila por evento. En dobles, member_id es quien inscribe y
-- pareja_member_id su compañero(a); los dos quedan ocupados en ese horario.
CREATE TABLE IF NOT EXISTS public.nac_inscripcion_eventos (
  id                BIGSERIAL PRIMARY KEY,
  inscripcion_id    BIGINT NOT NULL REFERENCES public.nac_inscripciones(id) ON DELETE CASCADE,
  evento            TEXT NOT NULL REFERENCES public.nac_eventos(codigo),
  member_id         BIGINT NOT NULL,
  pareja_member_id  BIGINT,
  precio            NUMERIC(6,2) NOT NULL,
  es_natural        BOOLEAN NOT NULL DEFAULT false,
  requiere          TEXT REFERENCES public.nac_eventos(codigo),  -- natural de la que depende (superior)
  estado            TEXT NOT NULL DEFAULT 'activa'
                      CHECK (estado IN ('activa','cancelada','cancelada_penalidad')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelada_at      TIMESTAMPTZ,
  nota_admin        TEXT,
  CHECK (pareja_member_id IS NULL OR pareja_member_id <> member_id)
);
CREATE INDEX IF NOT EXISTS nac_ie_insc_idx   ON public.nac_inscripcion_eventos (inscripcion_id);
CREATE INDEX IF NOT EXISTS nac_ie_member_idx ON public.nac_inscripcion_eventos (member_id) WHERE estado = 'activa';
CREATE INDEX IF NOT EXISTS nac_ie_pareja_idx ON public.nac_inscripcion_eventos (pareja_member_id) WHERE estado = 'activa';

-- Intentos de verificación por fecha de nacimiento (freno a quien adivine fechas).
CREATE TABLE IF NOT EXISTS public.nac_verificaciones (
  id         BIGSERIAL PRIMARY KEY,
  member_id  BIGINT NOT NULL,
  ok         BOOLEAN NOT NULL,
  at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nac_verif_idx ON public.nac_verificaciones (member_id, at DESC);

ALTER TABLE public.nac_inscripciones       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nac_inscripcion_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nac_verificaciones      ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.nac_inscripciones, public.nac_inscripcion_eventos, public.nac_verificaciones FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.nac_inscripciones_id_seq, public.nac_inscripcion_eventos_id_seq, public.nac_verificaciones_id_seq FROM anon, authenticated;

-- Lectura solo para el administrador (y service_role, que no pasa por RLS).
-- Todas las escrituras van por las funciones de abajo.
DROP POLICY IF EXISTS nac_insc_admin_select ON public.nac_inscripciones;
CREATE POLICY nac_insc_admin_select ON public.nac_inscripciones FOR SELECT TO authenticated
  USING (auth.uid() = 'b1c91ed0-edc2-42ea-b64e-346a0659dcad'::uuid);
DROP POLICY IF EXISTS nac_ie_admin_select ON public.nac_inscripcion_eventos;
CREATE POLICY nac_ie_admin_select ON public.nac_inscripcion_eventos FOR SELECT TO authenticated
  USING (auth.uid() = 'b1c91ed0-edc2-42ea-b64e-346a0659dcad'::uuid);
GRANT SELECT ON public.nac_inscripciones, public.nac_inscripcion_eventos TO authenticated;

-- Interruptores. Cerradas por defecto: se abren desde nacionales-admin.html.
INSERT INTO public.app_settings (key, value) VALUES
  ('nacionales_inscripciones_open', 'false'),
  ('nacionales_ignorar_deadline',   'false')
ON CONFLICT (key) DO NOTHING;


-- ── 3. Ayudantes internos (no ejecutables por anon) ────────────────────────
CREATE OR REPLACE FUNCTION internal_security.nac_es_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT coalesce(auth.uid() = 'b1c91ed0-edc2-42ea-b64e-346a0659dcad'::uuid, false)
$$;

CREATE OR REPLACE FUNCTION internal_security.nac_sexo(raw TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE
    WHEN upper(btrim(coalesce(raw,''))) IN ('M','MALE','MASCULINO','H','HOMBRE') THEN 'M'
    WHEN upper(btrim(coalesce(raw,''))) IN ('F','FEMALE','FEMENINO','MUJER')     THEN 'F'
  END
$$;

-- Último día del torneo: la membresía tiene que cubrirlo.
CREATE OR REPLACE FUNCTION internal_security.nac_fin_torneo()
RETURNS DATE LANGUAGE sql IMMUTABLE SET search_path = '' AS $$ SELECT DATE '2026-12-20' $$;

-- Fecha límite del reglamento: viernes 4 de diciembre de 2026, 11:00 p.m. AST.
CREATE OR REPLACE FUNCTION internal_security.nac_abiertas()
RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT coalesce((SELECT value FROM public.app_settings WHERE key = 'nacionales_inscripciones_open'), 'false') = 'true'
     AND ( now() < TIMESTAMPTZ '2026-12-04 23:00:00-04'
        OR coalesce((SELECT value FROM public.app_settings WHERE key = 'nacionales_ignorar_deadline'), 'false') = 'true')
$$;

CREATE OR REPLACE FUNCTION internal_security.nac_jugador(p_member_id BIGINT)
RETURNS TABLE (member_id BIGINT, nombre TEXT, sexo TEXT, dob DATE, edad INT,
               rating INT, club TEXT, vence DATE)
LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT b."Member ID"::bigint,
         btrim(concat_ws(' ', btrim(b."First Name"), btrim(b."Last Name"))),
         internal_security.nac_sexo(b."Sex"),
         public.fprtm_parse_fecha(b."Date of Birth"),
         2026 - extract(YEAR FROM public.fprtm_parse_fecha(b."Date of Birth"))::int,   -- edad al 31-dic-2026
         round(coalesce(b."New Rating"::numeric, b."Rating"::numeric))::int,
         nullif(btrim(b."Club"), ''),
         public.fprtm_parse_fecha(b."Expiration Date")
  FROM public."Base de Datos" b
  WHERE b."Member ID" = p_member_id
  LIMIT 1
$$;

-- Categoría natural por edad: la menor que admite su edad (7, 9, 11, 13, 15, 19).
CREATE OR REPLACE FUNCTION internal_security.nac_natural_edad(p_edad INT, p_sexo TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE
    WHEN p_edad IS NULL OR p_edad > 19 THEN NULL
    WHEN p_edad <= 7 THEN 'u7'
    WHEN p_sexo NOT IN ('M','F') OR p_sexo IS NULL THEN NULL
    ELSE 'u' || (SELECT min(x) FROM unnest(ARRAY[9,11,13,15,19]) x WHERE p_edad <= x)::text || lower(p_sexo)
  END
$$;

-- Categoría natural por rating: la menor que admite su rating. Más de 1900: ninguna.
CREATE OR REPLACE FUNCTION internal_security.nac_natural_rating(p_rating INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE WHEN p_rating IS NULL OR p_rating > 1900 THEN NULL
              ELSE 'r' || (SELECT min(x) FROM unnest(ARRAY[1500,1600,1700,1800,1900]) x WHERE p_rating <= x)::text
         END
$$;

-- ¿Puede este jugador jugar este evento? Y si es superior, ¿de qué natural depende?
CREATE OR REPLACE FUNCTION internal_security.nac_elegible(p_evento TEXT, p_edad INT, p_sexo TEXT, p_rating INT,
                                                          OUT elegible BOOLEAN, OUT es_natural BOOLEAN, OUT requiere TEXT)
LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE
  e        public.nac_eventos;
  nat_e    TEXT := internal_security.nac_natural_edad(p_edad, p_sexo);
  nat_r    TEXT := internal_security.nac_natural_rating(p_rating);
  escala   INT[] := ARRAY[1500,1600,1700,1800,1900];
  i        INT;
BEGIN
  elegible := false; es_natural := false; requiere := NULL;
  SELECT * INTO e FROM public.nac_eventos WHERE codigo = p_evento;
  IF NOT FOUND THEN RETURN; END IF;

  IF e.tipo = 'edad' THEN
    IF e.codigo = nat_e THEN elegible := true; es_natural := true;
    ELSIF nat_e IN ('u13f','u15f') AND e.codigo = 'u19f' THEN elegible := true; requiere := nat_e;
    ELSIF nat_e IN ('u13m','u15m') AND e.codigo = 'u19m' THEN elegible := true; requiere := nat_e;
    END IF;
  ELSIF e.tipo = 'rating' THEN
    IF e.codigo = nat_r THEN elegible := true; es_natural := true;
    ELSIF nat_r IS NOT NULL THEN
      i := array_position(escala, substr(nat_r, 2)::int);
      IF e.rating_max IN (escala[i+1], escala[i+2]) THEN elegible := true; requiere := nat_r; END IF;
    END IF;
  ELSIF e.tipo = 'abierto' THEN
    elegible := (e.sexo = p_sexo);
  ELSIF e.tipo = 'senior' THEN
    elegible := (p_edad >= e.edad_min);
  ELSIF e.tipo = 'dobles' THEN
    elegible := (e.sexo = 'X' AND p_sexo IN ('M','F')) OR e.sexo = p_sexo;
  END IF;
END;
$$;

-- Eventos activos de un jugador (como titular o como pareja), en inscripciones no canceladas.
CREATE OR REPLACE FUNCTION internal_security.nac_eventos_activos(p_member_id BIGINT)
RETURNS TABLE (evento TEXT, fila_id BIGINT, inscripcion_id BIGINT, es_titular BOOLEAN,
               otro_member_id BIGINT, estado_inscripcion TEXT, es_natural BOOLEAN, requiere TEXT)
LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT ie.evento, ie.id, ie.inscripcion_id, ie.member_id = p_member_id,
         CASE WHEN ie.member_id = p_member_id THEN ie.pareja_member_id ELSE ie.member_id END,
         i.estado, ie.es_natural, ie.requiere
  FROM public.nac_inscripcion_eventos ie
  JOIN public.nac_inscripciones i ON i.id = ie.inscripcion_id
  WHERE ie.estado = 'activa' AND i.estado <> 'cancelada'
    AND (ie.member_id = p_member_id OR ie.pareja_member_id = p_member_id)
$$;

-- Verifica Member ID + fecha de nacimiento. Registra el intento.
-- Devuelve: 'ok' | 'bloqueado' | 'no_coincide'
CREATE OR REPLACE FUNCTION internal_security.nac_check_dob(p_member_id BIGINT, p_dob DATE)
RETURNS TEXT LANGUAGE plpgsql VOLATILE SET search_path = '' AS $$
DECLARE v_dob DATE; v_fallos INT;
BEGIN
  SELECT count(*) INTO v_fallos FROM public.nac_verificaciones
   WHERE member_id = p_member_id AND NOT ok AND at > now() - INTERVAL '15 minutes';
  IF v_fallos >= 5 THEN RETURN 'bloqueado'; END IF;
  SELECT dob INTO v_dob FROM internal_security.nac_jugador(p_member_id);
  IF v_dob IS NOT NULL AND p_dob IS NOT NULL AND v_dob = p_dob THEN
    RETURN 'ok';
  END IF;
  INSERT INTO public.nac_verificaciones (member_id, ok) VALUES (coalesce(p_member_id, 0), false);
  RETURN 'no_coincide';
END;
$$;

CREATE OR REPLACE FUNCTION internal_security.nac_error_dob(p_res TEXT)
RETURNS JSONB LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE p_res
    WHEN 'bloqueado' THEN jsonb_build_object('ok', false, 'error', 'bloqueado',
      'mensaje', 'Demasiados intentos con fechas que no coinciden. Espera 15 minutos o contacta a Joel Vega (787-248-3994).')
    ELSE jsonb_build_object('ok', false, 'error', 'dob',
      'mensaje', 'La fecha de nacimiento no coincide con el registro de la FPTM. Revísala o contacta a Joel Vega (787-248-3994).')
  END
$$;

REVOKE ALL ON FUNCTION internal_security.nac_es_admin(), internal_security.nac_sexo(TEXT),
  internal_security.nac_fin_torneo(), internal_security.nac_abiertas(),
  internal_security.nac_jugador(BIGINT), internal_security.nac_natural_edad(INT, TEXT),
  internal_security.nac_natural_rating(INT), internal_security.nac_elegible(TEXT, INT, TEXT, INT),
  internal_security.nac_eventos_activos(BIGINT), internal_security.nac_check_dob(BIGINT, DATE),
  internal_security.nac_error_dob(TEXT)
  FROM PUBLIC, anon, authenticated;


-- ── 4. Funciones públicas (vía envolturas) ─────────────────────────────────

-- 4.1 Verificar identidad y traer lo necesario para escoger categorías.
CREATE OR REPLACE FUNCTION internal_security.nac_verificar(p_member_id BIGINT, p_dob DATE)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE j RECORD; v_res TEXT; v_insc JSONB;
BEGIN
  v_res := internal_security.nac_check_dob(p_member_id, p_dob);
  IF v_res <> 'ok' THEN RETURN internal_security.nac_error_dob(v_res); END IF;
  SELECT * INTO j FROM internal_security.nac_jugador(p_member_id);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'evento', a.evento, 'estado_inscripcion', a.estado_inscripcion,
           'es_titular', a.es_titular, 'es_natural', a.es_natural, 'requiere', a.requiere,
           'pareja', CASE WHEN a.otro_member_id IS NULL THEN NULL ELSE
             (SELECT jsonb_build_object('member_id', o.member_id, 'nombre', o.nombre)
                FROM internal_security.nac_jugador(a.otro_member_id) o) END)), '[]'::jsonb)
    INTO v_insc
    FROM internal_security.nac_eventos_activos(p_member_id) a;

  RETURN jsonb_build_object(
    'ok', true,
    'abiertas', internal_security.nac_abiertas(),
    'jugador', jsonb_build_object(
      'member_id', j.member_id, 'nombre', j.nombre, 'sexo', j.sexo, 'edad', j.edad,
      'rating', j.rating, 'club', j.club, 'membresia_vence', j.vence,
      'membresia_ok', coalesce(j.vence >= internal_security.nac_fin_torneo(), false),
      'natural_edad', internal_security.nac_natural_edad(j.edad, j.sexo),
      'natural_rating', internal_security.nac_natural_rating(j.rating)),
    'inscrito', v_insc);
END;
$$;

-- 4.2 Buscar pareja para un evento de dobles. Solo miembros con membresía
--     vigente durante todo el torneo y del sexo que pide el evento. Nunca
--     devuelve fecha de nacimiento ni sexo.
CREATE OR REPLACE FUNCTION internal_security.nac_parejas(p_member_id BIGINT, p_dob DATE, p_evento TEXT, p_q TEXT)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE yo RECORD; e public.nac_eventos; v_res TEXT; q TEXT; v_out JSONB;
BEGIN
  v_res := internal_security.nac_check_dob(p_member_id, p_dob);
  IF v_res <> 'ok' THEN RETURN internal_security.nac_error_dob(v_res); END IF;
  SELECT * INTO e FROM public.nac_eventos WHERE codigo = p_evento AND tipo = 'dobles';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'evento', 'mensaje', 'Evento de dobles no válido.'); END IF;
  SELECT * INTO yo FROM internal_security.nac_jugador(p_member_id);

  q := translate(lower(btrim(coalesce(p_q, ''))), 'áàäâãéèëêíìïîóòöôõúùüûñç', 'aaaaaeeeeiiiiooooouuuunc');
  IF length(q) < 2 THEN RETURN jsonb_build_object('ok', true, 'parejas', '[]'::jsonb); END IF;

  WITH cand AS (
    SELECT b."Member ID"::bigint AS mid
    FROM public."Base de Datos" b
    WHERE b."Member ID" <> p_member_id
      AND public.fprtm_parse_fecha(b."Expiration Date") >= internal_security.nac_fin_torneo()
      AND CASE e.sexo WHEN 'X' THEN internal_security.nac_sexo(b."Sex") IN ('M','F')
                                  AND internal_security.nac_sexo(b."Sex") <> yo.sexo
                      ELSE internal_security.nac_sexo(b."Sex") = e.sexo END
      AND ( b."Member ID"::text = q
         OR translate(lower(concat_ws(' ', btrim(b."First Name"), btrim(b."Last Name"))),
                      'áàäâãéèëêíìïîóòöôõúùüûñç', 'aaaaaeeeeiiiiooooouuuunc') LIKE '%' || q || '%')
    ORDER BY b."Last Name", b."First Name"
    LIMIT 8
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'member_id', j.member_id, 'nombre', j.nombre, 'club', j.club, 'rating', j.rating,
           'motivo', (SELECT CASE
               WHEN a.evento = e.codigo THEN 'Ya tiene pareja en este evento'
               ELSE 'Ya está inscrito en ' || ev.nombre || ' a la misma hora' END
             FROM internal_security.nac_eventos_activos(j.member_id) a
             JOIN public.nac_eventos ev ON ev.codigo = a.evento
             WHERE ev.fecha = e.fecha AND ev.hora = e.hora
             ORDER BY (a.evento = e.codigo) DESC LIMIT 1))
         ORDER BY j.nombre), '[]'::jsonb)
    INTO v_out
    FROM cand c CROSS JOIN LATERAL internal_security.nac_jugador(c.mid) j;

  RETURN jsonb_build_object('ok', true, 'parejas', v_out);
END;
$$;

-- 4.3 Inscribir. p_eventos = [{"evento":"r1600"}, {"evento":"dx","pareja":10655}, …]
CREATE OR REPLACE FUNCTION internal_security.nac_inscribir(p_member_id BIGINT, p_dob DATE, p_eventos JSONB,
                                                           p_acepta BOOLEAN, p_reglamento TEXT)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  yo        RECORD;
  pa        RECORD;
  e         public.nac_eventos;
  el        RECORD;
  it        JSONB;
  v_res     TEXT;
  v_cod     TEXT;
  v_pareja  BIGINT;
  v_req     TEXT[] := '{}';
  v_exist   TEXT[];
  v_todos   TEXT[];
  v_choque  TEXT;
  v_total   NUMERIC := 0;
  v_id      BIGINT;
  v_filas   JSONB := '[]'::jsonb;
  err       CONSTANT TEXT := 'error';
BEGIN
  -- Identidad
  v_res := internal_security.nac_check_dob(p_member_id, p_dob);
  IF v_res <> 'ok' THEN RETURN internal_security.nac_error_dob(v_res); END IF;
  SELECT * INTO yo FROM internal_security.nac_jugador(p_member_id);

  IF NOT internal_security.nac_abiertas() THEN
    RETURN jsonb_build_object('ok', false, err, 'cerradas', 'mensaje', 'Las inscripciones de los Campeonatos Nacionales no están abiertas.');
  END IF;
  IF yo.vence IS NULL OR yo.vence < internal_security.nac_fin_torneo() THEN
    RETURN jsonb_build_object('ok', false, err, 'membresia',
      'mensaje', 'Tu membresía no cubre el torneo (hasta el 20 de diciembre). Renuévala en membresia.html antes de inscribirte.');
  END IF;
  IF p_acepta IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, err, 'reglamento', 'mensaje', 'Debes leer y aceptar el reglamento.');
  END IF;
  IF jsonb_typeof(p_eventos) <> 'array' OR jsonb_array_length(p_eventos) = 0 OR jsonb_array_length(p_eventos) > 22 THEN
    RETURN jsonb_build_object('ok', false, err, 'eventos', 'mensaje', 'Escoge al menos una categoría.');
  END IF;

  -- Serializa inscripciones: dos personas no pueden tomar a la misma pareja a la vez.
  LOCK TABLE public.nac_inscripcion_eventos IN SHARE ROW EXCLUSIVE MODE;

  SELECT coalesce(array_agg(evento), '{}') INTO v_exist FROM internal_security.nac_eventos_activos(p_member_id);

  -- Cada evento pedido: existe, no repetido, elegible, no inscrito ya
  FOR it IN SELECT * FROM jsonb_array_elements(p_eventos) LOOP
    v_cod := it->>'evento';
    SELECT * INTO e FROM public.nac_eventos WHERE codigo = v_cod;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, err, 'eventos', 'mensaje', 'Categoría no válida: ' || coalesce(v_cod, '—'));
    END IF;
    IF v_cod = ANY(v_req) THEN
      RETURN jsonb_build_object('ok', false, err, 'eventos', 'mensaje', e.nombre || ' está repetida.');
    END IF;
    IF v_cod = ANY(v_exist) THEN
      RETURN jsonb_build_object('ok', false, err, 'eventos', 'mensaje', 'Ya estás inscrito en ' || e.nombre || '.');
    END IF;
    SELECT * INTO el FROM internal_security.nac_elegible(v_cod, yo.edad, yo.sexo, yo.rating);
    IF NOT el.elegible THEN
      RETURN jsonb_build_object('ok', false, err, 'elegibilidad', 'mensaje', 'No eres elegible para ' || e.nombre || '.');
    END IF;
    v_req := v_req || v_cod;
  END LOOP;
  v_todos := v_exist || v_req;

  -- Superior: la natural tiene que estar (ya inscrita o en este envío)
  FOR v_cod IN SELECT unnest(v_req) LOOP
    SELECT * INTO el FROM internal_security.nac_elegible(v_cod, yo.edad, yo.sexo, yo.rating);
    IF el.requiere IS NOT NULL AND NOT (el.requiere = ANY(v_todos)) THEN
      RETURN jsonb_build_object('ok', false, err, 'natural', 'mensaje',
        'Para jugar ' || (SELECT nombre FROM public.nac_eventos WHERE codigo = v_cod)
        || ' tienes que inscribirte también en tu categoría natural, '
        || (SELECT nombre FROM public.nac_eventos WHERE codigo = el.requiere) || '.');
    END IF;
  END LOOP;

  -- Un solo evento por día y hora
  SELECT string_agg(nombre, ' y ' ORDER BY orden) INTO v_choque
    FROM public.nac_eventos x
   WHERE codigo = ANY(v_todos)
     AND (fecha, hora) IN (SELECT fecha, hora FROM public.nac_eventos
                            WHERE codigo = ANY(v_todos) GROUP BY fecha, hora HAVING count(*) > 1);
  IF v_choque IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, err, 'horario', 'mensaje', 'Estas categorías se juegan a la misma hora: ' || v_choque || '. Escoge solo una.');
  END IF;

  -- Dobles: pareja válida y libre
  FOR it IN SELECT * FROM jsonb_array_elements(p_eventos) LOOP
    SELECT * INTO e FROM public.nac_eventos WHERE codigo = it->>'evento';
    CONTINUE WHEN e.tipo <> 'dobles';
    v_pareja := nullif(it->>'pareja', '')::bigint;
    IF v_pareja IS NULL THEN
      RETURN jsonb_build_object('ok', false, err, 'pareja', 'mensaje', 'Escoge tu pareja para ' || e.nombre || '.');
    END IF;
    IF v_pareja = p_member_id THEN
      RETURN jsonb_build_object('ok', false, err, 'pareja', 'mensaje', 'No puedes ser tu propia pareja.');
    END IF;
    SELECT * INTO pa FROM internal_security.nac_jugador(v_pareja);
    IF pa.member_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, err, 'pareja', 'mensaje', 'Tu pareja de ' || e.nombre || ' no está en el registro de la FPTM.');
    END IF;
    IF pa.vence IS NULL OR pa.vence < internal_security.nac_fin_torneo() THEN
      RETURN jsonb_build_object('ok', false, err, 'pareja', 'mensaje', pa.nombre || ' no tiene membresía vigente durante todo el torneo.');
    END IF;
    IF (e.sexo = 'X' AND (pa.sexo IS NULL OR pa.sexo = yo.sexo)) OR (e.sexo <> 'X' AND pa.sexo IS DISTINCT FROM e.sexo) THEN
      RETURN jsonb_build_object('ok', false, err, 'pareja', 'mensaje', pa.nombre || ' no puede ser tu pareja en ' || e.nombre || '.');
    END IF;
    SELECT 'Ya tiene pareja en ' || e.nombre INTO v_choque
      FROM internal_security.nac_eventos_activos(v_pareja) a WHERE a.evento = e.codigo LIMIT 1;
    IF v_choque IS NULL THEN
      SELECT 'Ya está inscrito en ' || ev.nombre || ' a la misma hora' INTO v_choque
        FROM internal_security.nac_eventos_activos(v_pareja) a
        JOIN public.nac_eventos ev ON ev.codigo = a.evento
       WHERE ev.fecha = e.fecha AND ev.hora = e.hora LIMIT 1;
    END IF;
    IF v_choque IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, err, 'pareja', 'mensaje', pa.nombre || ': ' || v_choque || '.');
    END IF;
  END LOOP;

  -- Guardar
  SELECT coalesce(sum(precio), 0) INTO v_total FROM public.nac_eventos WHERE codigo = ANY(v_req);
  INSERT INTO public.nac_inscripciones (member_id, nombre, total, reglamento_version)
       VALUES (p_member_id, yo.nombre, v_total, left(coalesce(nullif(p_reglamento, ''), 'sin-version'), 40))
    RETURNING id INTO v_id;

  FOR it IN SELECT * FROM jsonb_array_elements(p_eventos) LOOP
    SELECT * INTO e FROM public.nac_eventos WHERE codigo = it->>'evento';
    SELECT * INTO el FROM internal_security.nac_elegible(e.codigo, yo.edad, yo.sexo, yo.rating);
    INSERT INTO public.nac_inscripcion_eventos (inscripcion_id, evento, member_id, pareja_member_id, precio, es_natural, requiere)
         VALUES (v_id, e.codigo, p_member_id,
                 CASE WHEN e.tipo = 'dobles' THEN (it->>'pareja')::bigint END,
                 e.precio, el.es_natural, el.requiere);
    v_filas := v_filas || jsonb_build_object('evento', e.codigo, 'nombre', e.nombre, 'precio', e.precio);
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'inscripcion_id', v_id, 'total', v_total, 'eventos', v_filas);
END;
$$;

REVOKE ALL ON FUNCTION internal_security.nac_verificar(BIGINT, DATE),
                       internal_security.nac_parejas(BIGINT, DATE, TEXT, TEXT),
                       internal_security.nac_inscribir(BIGINT, DATE, JSONB, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION internal_security.nac_verificar(BIGINT, DATE),
                          internal_security.nac_parejas(BIGINT, DATE, TEXT, TEXT),
                          internal_security.nac_inscribir(BIGINT, DATE, JSONB, BOOLEAN, TEXT) TO anon, authenticated;

-- Envolturas SECURITY INVOKER: lo único que PostgREST expone.
CREATE OR REPLACE FUNCTION public.nac_verificar(p_member_id BIGINT, p_dob DATE)
RETURNS JSONB LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
  SELECT internal_security.nac_verificar(p_member_id, p_dob) $$;
CREATE OR REPLACE FUNCTION public.nac_parejas(p_member_id BIGINT, p_dob DATE, p_evento TEXT, p_q TEXT)
RETURNS JSONB LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
  SELECT internal_security.nac_parejas(p_member_id, p_dob, p_evento, p_q) $$;
CREATE OR REPLACE FUNCTION public.nac_inscribir(p_member_id BIGINT, p_dob DATE, p_eventos JSONB, p_acepta BOOLEAN, p_reglamento TEXT)
RETURNS JSONB LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$
  SELECT internal_security.nac_inscribir(p_member_id, p_dob, p_eventos, p_acepta, p_reglamento) $$;

REVOKE ALL ON FUNCTION public.nac_verificar(BIGINT, DATE), public.nac_parejas(BIGINT, DATE, TEXT, TEXT),
                       public.nac_inscribir(BIGINT, DATE, JSONB, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nac_verificar(BIGINT, DATE), public.nac_parejas(BIGINT, DATE, TEXT, TEXT),
                          public.nac_inscribir(BIGINT, DATE, JSONB, BOOLEAN, TEXT) TO anon, authenticated;

-- Estado público de las inscripciones (para el banner de la página).
CREATE OR REPLACE FUNCTION internal_security.nac_estado()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object('abiertas', internal_security.nac_abiertas(),
                            'cierre', '2026-12-04T23:00:00-04:00')
$$;
REVOKE ALL ON FUNCTION internal_security.nac_estado() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION internal_security.nac_estado() TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.nac_estado()
RETURNS JSONB LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$ SELECT internal_security.nac_estado() $$;
REVOKE ALL ON FUNCTION public.nac_estado() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nac_estado() TO anon, authenticated;


-- ── 5. Administración (solo el UID administrador) ──────────────────────────

-- 5.1 Lista completa para el panel y los CSV (incluye DOB, sexo y email: solo admin).
CREATE OR REPLACE FUNCTION internal_security.nac_admin_listar()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v JSONB;
BEGIN
  IF NOT internal_security.nac_es_admin() THEN RAISE EXCEPTION 'Solo el administrador' USING ERRCODE = '42501'; END IF;
  SELECT coalesce(jsonb_agg(x ORDER BY (x->>'id')::bigint DESC), '[]'::jsonb) INTO v FROM (
    SELECT jsonb_build_object(
      'id', i.id, 'member_id', i.member_id, 'nombre', i.nombre, 'total', i.total, 'estado', i.estado,
      'created_at', i.created_at, 'aprobada_at', i.aprobada_at, 'cancelada_at', i.cancelada_at,
      'nota_admin', i.nota_admin, 'reglamento_version', i.reglamento_version,
      'jugador', (SELECT jsonb_build_object('first_name', btrim(b."First Name"), 'last_name', btrim(b."Last Name"),
                    'dob', public.fprtm_parse_fecha(b."Date of Birth"), 'sexo', internal_security.nac_sexo(b."Sex"),
                    'email', b."Email", 'club', nullif(btrim(b."Club"), ''), 'home_address', b."Home Address",
                    'rating', round(coalesce(b."New Rating"::numeric, b."Rating"::numeric))::int,
                    'membresia_vence', public.fprtm_parse_fecha(b."Expiration Date"))
                  FROM public."Base de Datos" b WHERE b."Member ID" = i.member_id),
      'eventos', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'fila_id', ie.id, 'evento', ie.evento, 'precio', ie.precio, 'estado', ie.estado,
                    'es_natural', ie.es_natural, 'requiere', ie.requiere, 'nota_admin', ie.nota_admin,
                    'pareja', CASE WHEN ie.pareja_member_id IS NULL THEN NULL ELSE
                      (SELECT jsonb_build_object('member_id', b."Member ID", 'first_name', btrim(b."First Name"),
                               'last_name', btrim(b."Last Name"),
                               'rating', round(coalesce(b."New Rating"::numeric, b."Rating"::numeric))::int,
                               'club', nullif(btrim(b."Club"), ''))
                         FROM public."Base de Datos" b WHERE b."Member ID" = ie.pareja_member_id) END)
                  ORDER BY ev.orden), '[]'::jsonb)
                  FROM public.nac_inscripcion_eventos ie JOIN public.nac_eventos ev ON ev.codigo = ie.evento
                  WHERE ie.inscripcion_id = i.id)
    ) AS x
    FROM public.nac_inscripciones i
  ) s;
  RETURN v;
END;
$$;

-- 5.2 Aprobar el pago (después de recibir la evidencia).
CREATE OR REPLACE FUNCTION internal_security.nac_admin_aprobar(p_id BIGINT, p_nota TEXT)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT internal_security.nac_es_admin() THEN RAISE EXCEPTION 'Solo el administrador' USING ERRCODE = '42501'; END IF;
  UPDATE public.nac_inscripciones
     SET estado = 'aprobada', aprobada_at = now(), aprobada_por = auth.uid(),
         nota_admin = coalesce(nullif(btrim(p_nota), ''), nota_admin)
   WHERE id = p_id AND estado = 'pendiente';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'mensaje', 'La inscripción no existe o no está pendiente.'); END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- 5.3 Cancelar una inscripción completa (p_fila_id NULL) o un solo evento.
--     Si se cancela una natural y el jugador sigue con una superior que
--     depende de ella, la natural queda como 'cancelada_penalidad'
--     (penalidad de rating de la Mesa Técnica + 3 W/O, reglamento §11).
--     Sin p_confirmar = true, devuelve la advertencia y no cambia nada.
CREATE OR REPLACE FUNCTION internal_security.nac_admin_cancelar(p_id BIGINT, p_fila_id BIGINT, p_confirmar BOOLEAN, p_nota TEXT)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_filas  BIGINT[];
  v_pen    BIGINT[];
  v_avisos TEXT;
BEGIN
  IF NOT internal_security.nac_es_admin() THEN RAISE EXCEPTION 'Solo el administrador' USING ERRCODE = '42501'; END IF;

  SELECT coalesce(array_agg(ie.id), '{}') INTO v_filas
    FROM public.nac_inscripcion_eventos ie
   WHERE ie.inscripcion_id = p_id AND ie.estado = 'activa' AND (p_fila_id IS NULL OR ie.id = p_fila_id);
  IF cardinality(v_filas) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'mensaje', 'No hay nada activo que cancelar.');
  END IF;

  -- Naturales canceladas cuya superior sigue activa (fuera de lo que se cancela)
  SELECT coalesce(array_agg(DISTINCT n.id), '{}'),
         string_agg(DISTINCT en.nombre || ' (sigue en ' || es.nombre || ')', '; ')
    INTO v_pen, v_avisos
    FROM public.nac_inscripcion_eventos n
    JOIN public.nac_eventos en ON en.codigo = n.evento
    JOIN public.nac_inscripcion_eventos s
      ON s.member_id = n.member_id AND s.requiere = n.evento AND s.estado = 'activa'
     AND NOT (s.id = ANY(v_filas))
    JOIN public.nac_inscripciones si ON si.id = s.inscripcion_id AND si.estado <> 'cancelada'
    JOIN public.nac_eventos es ON es.codigo = s.evento
   WHERE n.id = ANY(v_filas) AND n.es_natural;

  IF cardinality(v_pen) > 0 AND p_confirmar IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, 'requiere_confirmacion', true,
      'mensaje', 'Se cancela una categoría natural mientras el jugador sigue en una superior: ' || v_avisos
                 || '. La natural quedará como "Cancelada · penalidad (3 W/O)".');
  END IF;

  UPDATE public.nac_inscripcion_eventos
     SET estado = CASE WHEN id = ANY(v_pen) THEN 'cancelada_penalidad' ELSE 'cancelada' END,
         cancelada_at = now(), nota_admin = coalesce(nullif(btrim(p_nota), ''), nota_admin)
   WHERE id = ANY(v_filas);

  -- Si ya no queda nada activo, la inscripción entera queda cancelada.
  IF NOT EXISTS (SELECT 1 FROM public.nac_inscripcion_eventos WHERE inscripcion_id = p_id AND estado = 'activa') THEN
    UPDATE public.nac_inscripciones SET estado = 'cancelada', cancelada_at = now(),
           nota_admin = coalesce(nullif(btrim(p_nota), ''), nota_admin)
     WHERE id = p_id;
  END IF;
  RETURN jsonb_build_object('ok', true, 'penalidades', cardinality(v_pen));
END;
$$;

-- 5.4 Abrir/cerrar y prórroga.
CREATE OR REPLACE FUNCTION internal_security.nac_admin_config(p_abiertas BOOLEAN, p_prorroga BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT internal_security.nac_es_admin() THEN RAISE EXCEPTION 'Solo el administrador' USING ERRCODE = '42501'; END IF;
  IF p_abiertas IS NOT NULL THEN
    INSERT INTO public.app_settings (key, value, updated_at) VALUES ('nacionales_inscripciones_open', p_abiertas::text, now())
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
  END IF;
  IF p_prorroga IS NOT NULL THEN
    INSERT INTO public.app_settings (key, value, updated_at) VALUES ('nacionales_ignorar_deadline', p_prorroga::text, now())
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
  END IF;
  RETURN jsonb_build_object('ok', true, 'abiertas', internal_security.nac_abiertas(),
    'interruptor', (SELECT value FROM public.app_settings WHERE key = 'nacionales_inscripciones_open'),
    'prorroga',    (SELECT value FROM public.app_settings WHERE key = 'nacionales_ignorar_deadline'));
END;
$$;

-- 5.5 Slug de Stadium por evento (cuando se cree el torneo en Stadium).
CREATE OR REPLACE FUNCTION internal_security.nac_admin_slug(p_evento TEXT, p_slug TEXT)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT internal_security.nac_es_admin() THEN RAISE EXCEPTION 'Solo el administrador' USING ERRCODE = '42501'; END IF;
  UPDATE public.nac_eventos SET stadium_slug = nullif(btrim(p_slug), '') WHERE codigo = p_evento;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'mensaje', 'Evento no existe.'); END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION internal_security.nac_admin_listar(), internal_security.nac_admin_aprobar(BIGINT, TEXT),
  internal_security.nac_admin_cancelar(BIGINT, BIGINT, BOOLEAN, TEXT), internal_security.nac_admin_config(BOOLEAN, BOOLEAN),
  internal_security.nac_admin_slug(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal_security.nac_admin_listar(), internal_security.nac_admin_aprobar(BIGINT, TEXT),
  internal_security.nac_admin_cancelar(BIGINT, BIGINT, BOOLEAN, TEXT), internal_security.nac_admin_config(BOOLEAN, BOOLEAN),
  internal_security.nac_admin_slug(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.nac_admin_listar()
RETURNS JSONB LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$ SELECT internal_security.nac_admin_listar() $$;
CREATE OR REPLACE FUNCTION public.nac_admin_aprobar(p_id BIGINT, p_nota TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$ SELECT internal_security.nac_admin_aprobar(p_id, p_nota) $$;
CREATE OR REPLACE FUNCTION public.nac_admin_cancelar(p_id BIGINT, p_fila_id BIGINT DEFAULT NULL, p_confirmar BOOLEAN DEFAULT false, p_nota TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$ SELECT internal_security.nac_admin_cancelar(p_id, p_fila_id, p_confirmar, p_nota) $$;
CREATE OR REPLACE FUNCTION public.nac_admin_config(p_abiertas BOOLEAN DEFAULT NULL, p_prorroga BOOLEAN DEFAULT NULL)
RETURNS JSONB LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$ SELECT internal_security.nac_admin_config(p_abiertas, p_prorroga) $$;
CREATE OR REPLACE FUNCTION public.nac_admin_slug(p_evento TEXT, p_slug TEXT)
RETURNS JSONB LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = '' AS $$ SELECT internal_security.nac_admin_slug(p_evento, p_slug) $$;

REVOKE ALL ON FUNCTION public.nac_admin_listar(), public.nac_admin_aprobar(BIGINT, TEXT),
  public.nac_admin_cancelar(BIGINT, BIGINT, BOOLEAN, TEXT), public.nac_admin_config(BOOLEAN, BOOLEAN),
  public.nac_admin_slug(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nac_admin_listar(), public.nac_admin_aprobar(BIGINT, TEXT),
  public.nac_admin_cancelar(BIGINT, BIGINT, BOOLEAN, TEXT), public.nac_admin_config(BOOLEAN, BOOLEAN),
  public.nac_admin_slug(TEXT, TEXT) TO authenticated;


-- ── 6. Vista para Kileaaa ──────────────────────────────────────────────────
-- Inscritos APROBADOS, uno por fila y evento, con su Member ID. Security
-- invoker: solo la ve el administrador (RLS) o service_role (Kileaaa en el
-- servidor). En dobles sale una fila por pareja.
CREATE OR REPLACE VIEW public.nac_inscritos_aprobados WITH (security_invoker = true) AS
SELECT ev.codigo        AS evento,
       ev.nombre        AS evento_nombre,
       ev.tipo          AS evento_tipo,
       ev.fecha, ev.hora, ev.area,
       ie.member_id,
       ie.pareja_member_id,
       ie.es_natural,
       i.id             AS inscripcion_id,
       i.aprobada_at
FROM public.nac_inscripcion_eventos ie
JOIN public.nac_inscripciones i ON i.id = ie.inscripcion_id
JOIN public.nac_eventos ev      ON ev.codigo = ie.evento
WHERE i.estado = 'aprobada' AND ie.estado = 'activa';
REVOKE ALL ON public.nac_inscritos_aprobados FROM PUBLIC, anon;
GRANT SELECT ON public.nac_inscritos_aprobados TO authenticated, service_role;


-- ── 7. Comprobaciones finales ──────────────────────────────────────────────
DO $chk$
BEGIN
  IF has_table_privilege('anon', 'public.nac_inscripciones', 'SELECT')
  OR has_table_privilege('anon', 'public.nac_inscripcion_eventos', 'SELECT')
  OR has_table_privilege('anon', 'public.nac_verificaciones', 'SELECT')
  OR has_table_privilege('anon', 'public.nac_inscritos_aprobados', 'SELECT') THEN
    RAISE EXCEPTION 'Inscripciones de Nacionales expuestas a anon';
  END IF;
  IF has_function_privilege('anon', 'public.nac_admin_listar()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Funciones de admin ejecutables por anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname LIKE 'nac\_%' AND p.prosecdef) THEN
    RAISE EXCEPTION 'Hay funciones nac_* SECURITY DEFINER en public';
  END IF;
END $chk$;

COMMIT;

SELECT 'nacionales_2026 OK' AS resultado;
