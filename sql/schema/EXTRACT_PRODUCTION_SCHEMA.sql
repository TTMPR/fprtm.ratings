-- ============================================================================
-- Kileaaa · Fase 1.0 — Extracción de metadatos del esquema de producción
--
-- SÓLO LECTURA. Es una única sentencia SELECT. No modifica nada: no hay DDL,
-- ni DML, ni cambios de permisos, ni de RLS. Se puede pegar tal cual en
-- Supabase → SQL Editor y ejecutar sobre producción sin riesgo.
--
-- No devuelve ni una sola fila de datos de las tablas: sólo metadatos del
-- catálogo. La única excepción son los conteos de filas (números, sin
-- contenido), que sirven para saber si `jugadores` sigue en uso.
--
-- Devuelve UN solo valor JSON. Cópialo entero y pégalo de vuelta.
--
-- Qué extrae, para las cinco tablas núcleo que faltan en el repositorio
-- ("Base de Datos", torneos, partidos, resultados_evento, jugadores):
--   columnas, tipos exactos, nulabilidad, defaults, identidad/generadas,
--   claves primarias, foráneas, únicas, restricciones CHECK, índices,
--   estado de RLS, políticas, triggers, funciones de trigger y secuencias.
--
-- Además: la vista miembros_alertas, la función update_updated_at(), todas
-- las políticas del esquema public (para verificar 090), las extensiones y
-- los buckets de Storage.
-- ============================================================================

WITH objetivo AS (
  SELECT c.oid, c.relname, c.relrowsecurity, c.relforcerowsecurity
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND c.relname IN ('Base de Datos','torneos','partidos','resultados_evento','jugadores')
)
SELECT jsonb_pretty(jsonb_build_object(

  'meta', jsonb_build_object(
    'extraido_en',   now(),
    'base_de_datos', current_database(),
    'version',       version(),
    'proposito',     'Fase 1.0 Kileaaa — recuperar el DDL que no está en Git'
  ),

  -- ── Existencia y conteo de filas de las tablas núcleo ────────────────────
  'tablas_nucleo', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla')
    FROM (
      SELECT jsonb_build_object(
        'tabla',            t.relname,
        'existe',           true,
        'rls_activado',     t.relrowsecurity,
        'rls_forzado',      t.relforcerowsecurity,
        'filas_estimadas',  (SELECT reltuples::bigint FROM pg_class WHERE oid = t.oid),
        'comentario',       obj_description(t.oid, 'pg_class')
      ) AS x
      FROM objetivo t
    ) q
  ),

  -- Conteo real de filas, por tabla (sólo números)
  'conteo_filas', jsonb_build_object(
    'Base de Datos',     (SELECT count(*) FROM public."Base de Datos"),
    'torneos',           (SELECT count(*) FROM public.torneos),
    'partidos',          (SELECT count(*) FROM public.partidos),
    'resultados_evento', (SELECT count(*) FROM public.resultados_evento),
    'jugadores',         (SELECT count(*) FROM public.jugadores)
  ),

  -- ── Columnas ────────────────────────────────────────────────────────────
  'columnas', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla', (x->>'posicion')::int)
    FROM (
      SELECT jsonb_build_object(
        'tabla',              t.relname,
        'posicion',           a.attnum,
        'columna',            a.attname,
        'tipo',               format_type(a.atttypid, a.atttypmod),
        'tipo_base',          tt.typname,
        'no_nulo',            a.attnotnull,
        'default',            pg_get_expr(ad.adbin, ad.adrelid),
        'identidad',          CASE a.attidentity WHEN 'a' THEN 'always'
                                                 WHEN 'd' THEN 'by default'
                                                 ELSE NULL END,
        'generada',           CASE a.attgenerated WHEN 's' THEN 'stored' ELSE NULL END,
        'colacion',           co.collname,
        'secuencia_asociada', pg_get_serial_sequence(
                                quote_ident('public') || '.' || quote_ident(t.relname),
                                a.attname),
        'comentario',         col_description(t.oid, a.attnum)
      ) AS x
      FROM objetivo t
      JOIN pg_attribute a  ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
      JOIN pg_type     tt  ON tt.oid = a.atttypid
      LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
      LEFT JOIN pg_collation co ON co.oid = a.attcollation AND co.collname <> 'default'
    ) q
  ),

  -- ── Restricciones: PK, FK, UNIQUE, CHECK, EXCLUDE ───────────────────────
  'restricciones', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla', x->>'tipo', x->>'nombre')
    FROM (
      SELECT jsonb_build_object(
        'tabla',      t.relname,
        'nombre',     con.conname,
        'tipo',       CASE con.contype WHEN 'p' THEN 'primary key'
                                       WHEN 'f' THEN 'foreign key'
                                       WHEN 'u' THEN 'unique'
                                       WHEN 'c' THEN 'check'
                                       WHEN 'x' THEN 'exclude'
                                       ELSE con.contype::text END,
        'definicion', pg_get_constraintdef(con.oid),
        'columnas',   (SELECT jsonb_agg(att.attname ORDER BY k.ord)
                       FROM unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord)
                       JOIN pg_attribute att
                         ON att.attrelid = con.conrelid AND att.attnum = k.attnum),
        'referencia', CASE WHEN con.contype = 'f'
                           THEN (SELECT rc.relname FROM pg_class rc WHERE rc.oid = con.confrelid)
                           ELSE NULL END
      ) AS x
      FROM objetivo t
      JOIN pg_constraint con ON con.conrelid = t.oid
    ) q
  ),

  -- ── Índices ─────────────────────────────────────────────────────────────
  'indices', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla', x->>'nombre')
    FROM (
      SELECT jsonb_build_object(
        'tabla',      t.relname,
        'nombre',     ic.relname,
        'definicion', pg_get_indexdef(i.indexrelid),
        'unico',      i.indisunique,
        'primaria',   i.indisprimary,
        'valido',     i.indisvalid
      ) AS x
      FROM objetivo t
      JOIN pg_index i  ON i.indrelid = t.oid
      JOIN pg_class ic ON ic.oid = i.indexrelid
    ) q
  ),

  -- ── Políticas RLS de las tablas núcleo ──────────────────────────────────
  'politicas_nucleo', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla', x->>'politica')
    FROM (
      SELECT jsonb_build_object(
        'tabla',     p.tablename,
        'politica',  p.policyname,
        'permisiva', p.permissive,
        'roles',     p.roles,
        'comando',   p.cmd,
        'using',     p.qual,
        'con_check', p.with_check
      ) AS x
      FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename IN ('Base de Datos','torneos','partidos','resultados_evento','jugadores')
    ) q
  ),

  -- ── Todas las políticas de public (para verificar 090) ──────────────────
  'politicas_todas', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla', x->>'politica')
    FROM (
      SELECT jsonb_build_object(
        'tabla',     p.tablename,
        'politica',  p.policyname,
        'permisiva', p.permissive,
        'roles',     p.roles,
        'comando',   p.cmd,
        'using',     p.qual,
        'con_check', p.with_check
      ) AS x
      FROM pg_policies p
      WHERE p.schemaname = 'public'
    ) q
  ),

  -- ── Estado de RLS en todo public ────────────────────────────────────────
  'rls_por_tabla', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla')
    FROM (
      SELECT jsonb_build_object(
        'tabla',   c.relname,
        'rls',     c.relrowsecurity,
        'forzado', c.relforcerowsecurity
      ) AS x
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
    ) q
  ),

  -- ── Triggers de las tablas núcleo + su función ──────────────────────────
  'triggers', (
    SELECT jsonb_agg(x ORDER BY x->>'tabla', x->>'trigger')
    FROM (
      SELECT jsonb_build_object(
        'tabla',           t.relname,
        'trigger',         tg.tgname,
        'definicion',      pg_get_triggerdef(tg.oid, true),
        'habilitado',      tg.tgenabled,
        'funcion',         pn.nspname || '.' || pr.proname
      ) AS x
      FROM objetivo t
      JOIN pg_trigger tg ON tg.tgrelid = t.oid AND NOT tg.tgisinternal
      JOIN pg_proc    pr ON pr.oid = tg.tgfoid
      JOIN pg_namespace pn ON pn.oid = pr.pronamespace
    ) q
  ),

  -- ── Funciones de trigger (una vez cada una, no por trigger) ─────────────
  'funciones_de_trigger', (
    SELECT jsonb_agg(x ORDER BY x->>'funcion')
    FROM (
      SELECT DISTINCT jsonb_build_object(
        'funcion',    pn.nspname || '.' || pr.proname,
        'definicion', pg_get_functiondef(pr.oid)
      ) AS x
      FROM objetivo t
      JOIN pg_trigger tg ON tg.tgrelid = t.oid AND NOT tg.tgisinternal
      JOIN pg_proc    pr ON pr.oid = tg.tgfoid
      JOIN pg_namespace pn ON pn.oid = pr.pronamespace
    ) q
  ),

  -- ── Secuencias del esquema public ───────────────────────────────────────
  'secuencias', (
    SELECT jsonb_agg(x ORDER BY x->>'secuencia')
    FROM (
      SELECT jsonb_build_object(
        'secuencia',  s.relname,
        'tipo',       format_type(sq.seqtypid, NULL),
        'inicio',     sq.seqstart,
        'incremento', sq.seqincrement,
        'minimo',     sq.seqmin,
        'maximo',     sq.seqmax,
        'ciclica',    sq.seqcycle,
        'propietaria', (
          SELECT dc.relname || '.' || da.attname
          FROM pg_depend d
          JOIN pg_class dc ON dc.oid = d.refobjid
          JOIN pg_attribute da ON da.attrelid = d.refobjid AND da.attnum = d.refobjsubid
          WHERE d.objid = s.oid AND d.deptype = 'a'
          LIMIT 1
        )
      ) AS x
      FROM pg_class s
      JOIN pg_namespace n ON n.oid = s.relnamespace
      JOIN pg_sequence sq ON sq.seqrelid = s.oid
      WHERE n.nspname = 'public' AND s.relkind = 'S'
    ) q
  ),

  -- ── Objetos que el repositorio referencia pero no define ────────────────
  'objetos_huerfanos', jsonb_build_object(
    'miembros_alertas', (
      SELECT jsonb_build_object(
        'existe',      true,
        'definicion',  pg_get_viewdef(c.oid, true),
        'tipo',        CASE c.relkind WHEN 'v' THEN 'view'
                                      WHEN 'm' THEN 'materialized view' END,
        'opciones',    c.reloptions,
        'comentario',  obj_description(c.oid, 'pg_class')
      )
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'miembros_alertas'
        AND c.relkind IN ('v','m')
    ),
    'update_updated_at', (
      SELECT jsonb_agg(jsonb_build_object(
        'existe',     true,
        'definicion', pg_get_functiondef(p.oid),
        'argumentos', pg_get_function_arguments(p.oid),
        'retorno',    pg_get_function_result(p.oid)
      ))
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'update_updated_at'
    )
  ),

  -- ── Inventario general de public (para comparar con el manifiesto) ──────
  'inventario_public', jsonb_build_object(
    'tablas', (
      SELECT jsonb_agg(c.relname ORDER BY c.relname)
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
    ),
    'vistas', (
      SELECT jsonb_agg(c.relname ORDER BY c.relname)
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('v','m')
    ),
    'funciones', (
      SELECT jsonb_agg(p.proname ORDER BY p.proname)
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
    )
  ),

  -- ── Extensiones y Storage ───────────────────────────────────────────────
  'extensiones', (
    SELECT jsonb_agg(jsonb_build_object('nombre', e.extname, 'version', e.extversion)
                     ORDER BY e.extname)
    FROM pg_extension e
  ),

  'storage_buckets', (
    SELECT jsonb_agg(jsonb_build_object('id', b.id, 'nombre', b.name, 'publico', b.public)
                     ORDER BY b.id)
    FROM storage.buckets b
  )

)) AS esquema_produccion;
