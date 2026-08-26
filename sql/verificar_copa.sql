-- ============================================================================
--  FPTM — Verificación de las inscripciones de la Copa Olímpica 2026
--  Correr en: Supabase → SQL Editor, después de:
--      1. sql/create_insc_equipos.sql
--      2. sql/create_busca_companero.sql
--
--  Es de SOLO LECTURA: no inserta, no borra, no cambia nada.
--
--  Devuelve una sola tabla. Lee la columna `estado`: si todo dice OK, la
--  plataforma está lista para abrir inscripciones. Cualquier "FALTA" o
--  "REVISAR" trae en `detalle` qué hacer.
-- ============================================================================

WITH
-- ── Tablas y vistas ────────────────────────────────────────────────────────
objetos AS (
  SELECT * FROM (VALUES
    ('insc_equipos',                  'tabla'),
    ('insc_divisiones',               'tabla'),
    ('insc_busca_companero',          'tabla'),
    ('insc_equipos_publico',          'vista'),
    ('insc_equipos_cupos',            'vista'),
    ('insc_busca_companero_publico',  'vista')
  ) AS t(nombre, tipo)
),
chk_objetos AS (
  SELECT '1. ' || o.tipo || ' ' || o.nombre AS control,
         CASE WHEN c.oid IS NULL THEN 'FALTA' ELSE 'OK' END AS estado,
         CASE WHEN c.oid IS NULL
              THEN 'No existe — corre el script que lo crea'
              ELSE 'presente' END AS detalle
    FROM objetos o
    LEFT JOIN pg_class c
      ON c.relname = o.nombre
     AND c.relnamespace = 'public'::regnamespace
),

-- ── Columnas que añadió la última versión ──────────────────────────────────
cols AS (
  SELECT * FROM (VALUES
    ('insc_equipos',                 'credito'),
    ('insc_divisiones',              'permite_reserva_solo'),
    ('insc_divisiones',              'reserva_rating_min'),
    ('insc_equipos_publico',         'cap_member_id'),
    ('insc_equipos_cupos',           'esperando_companero'),
    ('insc_equipos_cupos',           'en_revision'),
    ('insc_busca_companero_publico', 'cupo_division_nombre')
  ) AS t(tabla, columna)
),
chk_cols AS (
  SELECT '2. ' || c.tabla || '.' || c.columna AS control,
         CASE WHEN i.column_name IS NULL THEN 'FALTA' ELSE 'OK' END AS estado,
         CASE WHEN i.column_name IS NULL
              THEN 'Vuelve a correr create_insc_equipos.sql (trae los ALTER)'
              ELSE 'presente' END AS detalle
    FROM cols c
    LEFT JOIN information_schema.columns i
      ON i.table_schema = 'public' AND i.table_name = c.tabla
     AND i.column_name  = c.columna
),

-- ── El compañero tiene que poder ir vacío (cupo comprado sin pareja) ───────
chk_nullable AS (
  SELECT '3. insc_equipos.comp_nombre admite NULL' AS control,
         CASE WHEN is_nullable = 'YES' THEN 'OK' ELSE 'FALTA' END AS estado,
         CASE WHEN is_nullable = 'YES' THEN 'correcto'
              ELSE 'Sigue NOT NULL: sin esto no se puede comprar cupo sin pareja' END AS detalle
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='insc_equipos' AND column_name='comp_nombre'
),

-- ── Estados nuevos admitidos por el CHECK ─────────────────────────────────
chk_estados AS (
  SELECT '4. estados nuevos permitidos' AS control,
         CASE WHEN pg_get_constraintdef(oid) LIKE '%esperando_companero%'
               AND pg_get_constraintdef(oid) LIKE '%revision_tecnica%'
               AND pg_get_constraintdef(oid) LIKE '%credito%'
              THEN 'OK' ELSE 'FALTA' END AS estado,
         'esperando_companero / revision_tecnica / credito' AS detalle
    FROM pg_constraint
   WHERE conname = 'insc_equipos_estado_chk'
),

-- ── Funciones ─────────────────────────────────────────────────────────────
funcs AS (
  SELECT unnest(ARRAY[
    'inscribir_equipo','insc_equipos_liberar','reservar_cupo_solo',
    'nombrar_companero','resolver_revision_tecnica','liberar_cupo_con_credito',
    'publicar_busca_companero','retirar_busca_companero',
    'insc_es_menor','insc_rating_federativo',
    'insc_equipo_ocupa_cupo','insc_equipo_activo'
  ]) AS nombre
),
chk_funcs AS (
  SELECT '5. función ' || f.nombre AS control,
         CASE WHEN p.oid IS NULL THEN 'FALTA' ELSE 'OK' END AS estado,
         COALESCE('devuelve ' || pg_get_function_result(p.oid), 'No existe') AS detalle
    FROM funcs f
    LEFT JOIN pg_proc p
      ON p.proname = f.nombre AND p.pronamespace = 'public'::regnamespace
),

-- ── Seguridad: el público NO puede tocar las tablas con datos personales ──
chk_priv_deny AS (
  SELECT '6. anon SIN acceso a ' || t AS control,
         CASE WHEN to_regclass(t) IS NULL                      THEN 'FALTA'
              WHEN has_table_privilege('anon', t, 'SELECT')
                OR has_table_privilege('anon', t, 'INSERT')    THEN 'REVISAR'
              ELSE 'OK' END AS estado,
         CASE WHEN to_regclass(t) IS NULL THEN 'La tabla no existe todavía'
              WHEN has_table_privilege('anon', t, 'SELECT')
              THEN 'El público puede leer emails y teléfonos — revisa los REVOKE'
              ELSE 'correcto: solo llega por las vistas y las funciones' END AS detalle
    FROM unnest(ARRAY['public.insc_equipos','public.insc_busca_companero']) AS t
),
chk_priv_allow AS (
  SELECT '7. anon puede leer ' || t AS control,
         CASE WHEN to_regclass(t) IS NULL                     THEN 'FALTA'
              WHEN has_table_privilege('anon', t, 'SELECT')   THEN 'OK'
              ELSE 'FALTA' END AS estado,
         CASE WHEN to_regclass(t) IS NULL THEN 'No existe todavía'
              ELSE 'vista pública del portal' END AS detalle
    FROM unnest(ARRAY['public.insc_equipos_publico','public.insc_equipos_cupos',
                      'public.insc_busca_companero_publico','public.insc_divisiones']) AS t
),
chk_exec AS (
  SELECT '8. anon puede llamar ' || f AS control,
         CASE WHEN has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'OK' ELSE 'FALTA' END AS estado,
         'el portal inscribe por aquí' AS detalle
    FROM unnest(ARRAY['inscribir_equipo','reservar_cupo_solo','nombrar_companero',
                      'publicar_busca_companero']) AS f
    JOIN pg_proc p ON p.proname = f AND p.pronamespace = 'public'::regnamespace
),

-- ── Configuración del torneo ──────────────────────────────────────────────
-- La fila se lee como JSON a propósito: si el esquema está desactualizado y
-- le falta una columna, aquí sale NULL en vez de tumbar toda la verificación
-- justo en el caso que la verificación existe para detectar.
divs AS (
  SELECT to_jsonb(d) AS j FROM public.insc_divisiones d
   WHERE d.torneo = 'Copa Olímpica 2026'
),
chk_div AS (
  SELECT '9. ' || (j->>'nombre') AS control,
         CASE WHEN (j->>'precio')::NUMERIC > 0 AND (j->>'max_equipos')::INT > 0
              THEN 'OK' ELSE 'REVISAR' END AS estado,
         '$' || (j->>'precio') || ' · ' || (j->>'max_equipos') || ' equipos'
           || CASE WHEN (j->>'permite_reserva_solo')::BOOLEAN IS TRUE
                   THEN ' · admite cupo sin pareja desde rating '
                        || COALESCE(j->>'reserva_rating_min','—')
                   WHEN j ? 'permite_reserva_solo' THEN ''
                   ELSE ' · SIN la columna permite_reserva_solo (esquema viejo)' END AS detalle
    FROM divs
),
chk_total AS (
  SELECT '9. cupo total del torneo' AS control,
         CASE WHEN SUM((j->>'max_equipos')::INT) = 64 THEN 'OK' ELSE 'REVISAR' END AS estado,
         SUM((j->>'max_equipos')::INT) || ' equipos (la convocatoria dice 64)' AS detalle
    FROM divs
),
chk_ajustes AS (
  SELECT '10. ' || key AS control, 'OK' AS estado, value AS detalle
    FROM public.app_settings
   WHERE key IN ('inscripciones_open','insc_equipos_cierre','insc_equipos_reserva_horas')
),

-- ── Lo único que queda por hacer a mano ───────────────────────────────────
chk_abierto AS (
  SELECT '11. INSCRIPCIONES' AS control,
         CASE WHEN (SELECT value FROM public.app_settings WHERE key='inscripciones_open') = 'true'
              THEN 'ABIERTAS' ELSE 'CERRADAS' END AS estado,
         CASE WHEN (SELECT value FROM public.app_settings WHERE key='inscripciones_open') = 'true'
              THEN 'El público ya puede inscribirse'
              ELSE 'Ábrelas desde el panel de admin cuando quieras publicar' END AS detalle
)

SELECT * FROM chk_objetos
UNION ALL SELECT * FROM chk_cols
UNION ALL SELECT * FROM chk_nullable
UNION ALL SELECT * FROM chk_estados
UNION ALL SELECT * FROM chk_funcs
UNION ALL SELECT * FROM chk_priv_deny
UNION ALL SELECT * FROM chk_priv_allow
UNION ALL SELECT * FROM chk_exec
UNION ALL SELECT * FROM chk_div
UNION ALL SELECT * FROM chk_total
UNION ALL SELECT * FROM chk_ajustes
UNION ALL SELECT * FROM chk_abierto
ORDER BY 1;
