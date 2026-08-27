-- ============================================================================
-- 080 · Vistas públicas de la API
--
-- Depende de: 010 ("Base de Datos", torneos), 050 (clubs). Incluye fprtm_parse_fecha, del que dependen las vistas.
--
-- Origen: sql/create_api_publica.sql
-- Copiado literal: el módulo original ya es idempotente, autocontenido y
-- ordenado. Reescribirlo introduciría deriva respecto a producción.
-- ============================================================================

-- ============================================================================
--  FPTM — API pública para la página web oficial
--  Ejecutar en: Supabase → SQL Editor  (seguro de re-ejecutar)
--
--  Crea tres vistas de solo lectura pensadas para consumo desde el navegador
--  en un dominio de terceros (la página oficial de la federación):
--
--    public.api_jugadores  — atletas, ratings y estado de membresía
--    public.api_clubes     — clubes con logo e info de contacto
--    public.api_torneos    — torneos publicados
--
--  Por qué vistas y no la tabla directa: la política RLS de "Base de Datos"
--  es SELECT USING (true), que es a nivel de FILA, no de columna. Cualquiera
--  con la llave publicable puede pedir select=* y obtener Email, Home Address
--  y Date of Birth completos. El index.html se auto-limita a columnas no
--  sensibles por disciplina, pero eso no es una barrera. Estas vistas sí lo
--  son: solo existen las columnas que exponen.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- HELPER: fprtm_parse_fecha
-- "Date of Birth" y "Expiration Date" son columnas TEXT con tres formatos
-- históricos mezclados. Esta función replica _parseDOBStr() del index.html:
--
--     YYYY-MM-DD      ISO                       "2001-11-25"
--     D-Mon-YY(YY)    día-mes abreviado-año     "25-Nov-01"
--     M/D/YY(YY)      formato US                "11/25/2001"
--
-- Años de dos dígitos: < 30 → 2000s, >= 30 → 1900s (mismo pivote que el app).
-- Devuelve NULL en vez de fallar si el valor no cuadra con ningún formato.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fprtm_parse_fecha(raw TEXT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  t   TEXT;
  m   TEXT[];
  yy  INT;
  mm  INT;
  dd  INT;
  meses CONSTANT TEXT[] := ARRAY['jan','feb','mar','apr','may','jun',
                                 'jul','aug','sep','oct','nov','dec'];
BEGIN
  IF raw IS NULL THEN RETURN NULL; END IF;
  t := btrim(raw);
  IF t = '' THEN RETURN NULL; END IF;

  -- ISO: YYYY-MM-DD
  m := regexp_match(t, '^(\d{4})-(\d{2})-(\d{2})$');
  IF m IS NOT NULL THEN
    BEGIN
      RETURN make_date(m[1]::INT, m[2]::INT, m[3]::INT);
    EXCEPTION WHEN OTHERS THEN
      RETURN NULL;
    END;
  END IF;

  -- D-Mon-YY o D-Mon-YYYY
  m := regexp_match(t, '^(\d{1,2})-([A-Za-z]{3})-(\d{2,4})$');
  IF m IS NOT NULL THEN
    dd := m[1]::INT;
    mm := array_position(meses, lower(m[2]));
    yy := m[3]::INT;
    IF mm IS NULL THEN RETURN NULL; END IF;
    IF yy < 100 THEN yy := yy + CASE WHEN yy < 30 THEN 2000 ELSE 1900 END; END IF;
    BEGIN
      RETURN make_date(yy, mm, dd);
    EXCEPTION WHEN OTHERS THEN
      RETURN NULL;
    END;
  END IF;

  -- M/D/YY o M/D/YYYY
  m := regexp_match(t, '^(\d{1,2})/(\d{1,2})/(\d{2,4})$');
  IF m IS NOT NULL THEN
    mm := m[1]::INT;
    dd := m[2]::INT;
    yy := m[3]::INT;
    IF yy < 100 THEN yy := yy + CASE WHEN yy < 30 THEN 2000 ELSE 1900 END; END IF;
    BEGIN
      RETURN make_date(yy, mm, dd);
    EXCEPTION WHEN OTHERS THEN
      RETURN NULL;
    END;
  END IF;

  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fprtm_parse_fecha(TEXT) IS
  'Normaliza los formatos de fecha mezclados en "Base de Datos" a DATE. Espejo de _parseDOBStr() en index.html.';


-- ---------------------------------------------------------------------------
-- VISTA: api_jugadores
--
-- Expone SOLO lo acordado con la página web. Deliberadamente NO incluye:
--   Email, Home Address, ni la fecha de nacimiento completa.
-- En su lugar se publica el año de nacimiento y la edad, que es lo que hace
-- falta para categorías por edad sin entregar un dato identificativo.
--
-- rating: "New Rating" es el vigente tras el último torneo procesado; cuando
-- está vacío (jugador que aún no ha competido) se cae a "Rating" inicial.
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS public.api_jugadores;

CREATE VIEW public.api_jugadores
WITH (security_invoker = on)
AS
SELECT
  bd."Member ID"                                   AS member_id,
  btrim(bd."First Name")                           AS nombre,
  btrim(bd."Last Name")                            AS apellido,
  btrim(coalesce(bd."First Name", '') || ' ' || coalesce(bd."Last Name", ''))
                                                   AS nombre_completo,
  nullif(btrim(bd."Sex"), '')                      AS sexo,
  nullif(btrim(bd."Club"), '')                     AS club,
  nullif(btrim(bd."Escuela"), '')                  AS escuela,
  coalesce(bd."New Rating", bd."Rating")           AS rating,
  bd."Rating"                                      AS rating_inicio,
  extract(YEAR FROM public.fprtm_parse_fecha(bd."Date of Birth"))::INT
                                                   AS anio_nacimiento,
  CASE
    WHEN public.fprtm_parse_fecha(bd."Date of Birth") IS NULL THEN NULL
    ELSE extract(YEAR FROM age(current_date,
                              public.fprtm_parse_fecha(bd."Date of Birth")))::INT
  END                                              AS edad,
  coalesce(public.fprtm_parse_fecha(bd."Expiration Date") >= current_date, false)
                                                   AS membresia_activa,
  public.fprtm_parse_fecha(bd."Expiration Date")   AS membresia_vence,
  f.photo_url                                      AS foto_url,
  coalesce(f.is_minor, false)                      AS es_menor
FROM public."Base de Datos" bd
LEFT JOIN LATERAL (
  SELECT pr.photo_url, pr.is_minor
  FROM public.photo_requests pr
  WHERE pr.member_id = bd."Member ID"
    AND pr.status    = 'approved'
  ORDER BY pr.created_at DESC
  LIMIT 1
) f ON true;

COMMENT ON VIEW public.api_jugadores IS
  'API pública de atletas para la página web oficial. Sin email, dirección ni fecha de nacimiento completa.';


-- ---------------------------------------------------------------------------
-- VISTA: api_clubes
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS public.api_clubes;

CREATE VIEW public.api_clubes
WITH (security_invoker = on)
AS
SELECT
  c.name        AS club,
  c.logo_url,
  c.descripcion,
  c.direccion,
  c.telefono,
  c.encargado,
  (SELECT count(*)
     FROM public."Base de Datos" bd
    WHERE btrim(bd."Club") = c.name)  AS total_jugadores
FROM public.clubs c;

COMMENT ON VIEW public.api_clubes IS
  'API pública de clubes: logo, contacto y conteo de atletas.';


-- ---------------------------------------------------------------------------
-- VISTA: api_torneos
-- Solo torneos publicados y no borrados. El más reciente por fecha es el que
-- la página web debe mostrar como "torneo activo".
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS public.api_torneos;

CREATE VIEW public.api_torneos
WITH (security_invoker = on)
AS
SELECT
  t.id,
  t.nombre,
  t.fecha
FROM public.torneos t
WHERE coalesce(t.publicado, true) = true
  AND t.deleted_at IS NULL;

COMMENT ON VIEW public.api_torneos IS
  'API pública de torneos publicados. Ordenar por fecha desc para el torneo activo.';


-- ---------------------------------------------------------------------------
-- PERMISOS
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.api_jugadores TO anon, authenticated;
GRANT SELECT ON public.api_clubes    TO anon, authenticated;
GRANT SELECT ON public.api_torneos   TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fprtm_parse_fecha(TEXT) TO anon, authenticated;


-- ============================================================================
--  VERIFICACIÓN — corre esto después y revisa que se vea razonable
-- ============================================================================
-- SELECT member_id, nombre_completo, club, rating, anio_nacimiento,
--        edad, membresia_activa, membresia_vence
--   FROM public.api_jugadores
--  ORDER BY rating DESC NULLS LAST
--  LIMIT 20;
--
-- -- Cuántas fechas no se pudieron parsear (deberían ser pocas o ninguna):
-- SELECT count(*) FILTER (WHERE "Date of Birth"  IS NOT NULL
--                           AND public.fprtm_parse_fecha("Date of Birth")  IS NULL) AS dob_sin_parsear,
--        count(*) FILTER (WHERE "Expiration Date" IS NOT NULL
--                           AND public.fprtm_parse_fecha("Expiration Date") IS NULL) AS exp_sin_parsear
--   FROM public."Base de Datos";
