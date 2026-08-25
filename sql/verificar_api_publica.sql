-- ============================================================================
--  FPTM — Verificación de la API pública
--  Correr en: Supabase → SQL Editor, después de create_api_publica.sql
--  Es de solo lectura: no modifica nada.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. ¿Existen las tres vistas y tienen security_invoker activo?
--    Las tres deben aparecer con reloptions = {security_invoker=on}
-- ---------------------------------------------------------------------------
SELECT c.relname AS vista,
       c.reloptions,
       CASE WHEN c.reloptions::text LIKE '%security_invoker=on%'
            THEN 'OK' ELSE 'REVISAR' END AS estado
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname IN ('api_jugadores','api_clubes','api_torneos')
 ORDER BY c.relname;


-- ---------------------------------------------------------------------------
-- 2. ¿Ninguna columna sensible se coló en api_jugadores?
--    Debe devolver CERO filas.
-- ---------------------------------------------------------------------------
SELECT column_name AS columna_sensible_expuesta
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name   = 'api_jugadores'
   AND (   lower(column_name) LIKE '%email%'
        OR lower(column_name) LIKE '%correo%'
        OR lower(column_name) LIKE '%address%'
        OR lower(column_name) LIKE '%direcc%'
        OR lower(column_name) LIKE '%birth%'
        OR lower(column_name) LIKE '%phone%'
        OR lower(column_name) LIKE '%telefono%');


-- ---------------------------------------------------------------------------
-- 3. FECHAS QUE NO SE PUDIERON INTERPRETAR  ← lo más importante
--
--    "Date of Birth" y "Expiration Date" son TEXT con formatos mezclados.
--    Si algún valor no cuadra con ninguno de los tres formatos conocidos,
--    la vista lo devuelve como NULL, y eso tiene una consecuencia real:
--
--      - DOB sin interpretar  → el atleta sale sin edad ni año de nacimiento,
--                               y se cae de los filtros por categoría.
--      - EXP sin interpretar  → membresia_activa sale FALSE aunque la
--                               membresía esté vigente. La web lo mostraría
--                               como NO miembro.
--
--    Ambos conteos deberían ser 0. Si no lo son, corre la consulta 4.
-- ---------------------------------------------------------------------------
SELECT
  count(*) FILTER (WHERE "Date of Birth" IS NOT NULL
                     AND btrim("Date of Birth") <> ''
                     AND public.fprtm_parse_fecha("Date of Birth") IS NULL)
    AS dob_sin_interpretar,
  count(*) FILTER (WHERE "Expiration Date" IS NOT NULL
                     AND btrim("Expiration Date") <> ''
                     AND public.fprtm_parse_fecha("Expiration Date") IS NULL)
    AS exp_sin_interpretar,
  count(*) AS total_jugadores
  FROM public."Base de Datos";


-- ---------------------------------------------------------------------------
-- 4. Si la consulta 3 no dio 0: aquí están los valores problemáticos.
--    Muestra el formato exacto que hay que añadir a fprtm_parse_fecha().
-- ---------------------------------------------------------------------------
SELECT "Member ID"       AS member_id,
       "First Name"      AS nombre,
       "Last Name"       AS apellido,
       "Date of Birth"   AS dob_crudo,
       "Expiration Date" AS exp_crudo
  FROM public."Base de Datos"
 WHERE ("Date of Birth" IS NOT NULL AND btrim("Date of Birth") <> ''
        AND public.fprtm_parse_fecha("Date of Birth") IS NULL)
    OR ("Expiration Date" IS NOT NULL AND btrim("Expiration Date") <> ''
        AND public.fprtm_parse_fecha("Expiration Date") IS NULL)
 ORDER BY "Member ID"
 LIMIT 50;


-- ---------------------------------------------------------------------------
-- 5. ¿Puede el rol anon (la llave publicable) leer las vistas?
--    Debe devolver conteos > 0 sin error de permisos.
-- ---------------------------------------------------------------------------
SET ROLE anon;

SELECT (SELECT count(*) FROM public.api_jugadores) AS jugadores,
       (SELECT count(*) FROM public.api_clubes)    AS clubes,
       (SELECT count(*) FROM public.api_torneos)   AS torneos;

RESET ROLE;


-- ---------------------------------------------------------------------------
-- 6. Vistazo al top 15 — así se verá en la página web
-- ---------------------------------------------------------------------------
SELECT member_id, nombre_completo, sexo, club, rating,
       anio_nacimiento, edad, membresia_activa, membresia_vence
  FROM public.api_jugadores
 ORDER BY rating DESC NULLS LAST
 LIMIT 15;


-- ---------------------------------------------------------------------------
-- 7. Salud general de los datos que verá el público
-- ---------------------------------------------------------------------------
SELECT count(*)                                        AS total,
       count(*) FILTER (WHERE rating IS NULL)          AS sin_rating,
       count(*) FILTER (WHERE club IS NULL)            AS sin_club,
       count(*) FILTER (WHERE anio_nacimiento IS NULL) AS sin_anio_nacimiento,
       count(*) FILTER (WHERE membresia_activa)        AS membresias_activas,
       count(*) FILTER (WHERE foto_url IS NOT NULL)    AS con_foto,
       count(*) FILTER (WHERE foto_url IS NOT NULL AND es_menor) AS fotos_de_menores
  FROM public.api_jugadores;


-- ---------------------------------------------------------------------------
-- 8. Torneo activo y estado de inscripciones (lo que consume la web)
-- ---------------------------------------------------------------------------
SELECT * FROM public.api_torneos ORDER BY fecha DESC LIMIT 3;

SELECT key, value FROM public.app_settings WHERE key = 'inscripciones_open';
