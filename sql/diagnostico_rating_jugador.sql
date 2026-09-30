-- =============================================================================
-- Diagnóstico: ¿de dónde salió el rating actual de un jugador?
--
-- SOLO LEE. No cambia nada. Correr en Supabase → SQL Editor.
--
-- Cambia el número en la línea "51245 AS id" por el Member ID que quieras
-- revisar (51245 = Johnell Torres Ortega). Aparece en las dos consultas.
--
-- El SQL Editor muestra solo el resultado de la última consulta que corre,
-- así que selecciona cada una y córrela por separado (Ctrl+Enter).
-- =============================================================================


-- ---------------------------------------------------------------------------
-- CONSULTA 1 · Línea de tiempo: torneos, borradores y rating actual
--
-- Cómo leerla: en la columna "salto", cada torneo debería empezar con el
-- rating con que terminó el anterior (salto = 0). Un salto distinto de 0
-- marca el punto donde el rating cambió FUERA de un torneo publicado.
-- ---------------------------------------------------------------------------
WITH p AS (SELECT 51245 AS id),
torneos_jugador AS (
  SELECT t.fecha::timestamptz AS cuando,
         (t.deleted_at IS NOT NULL OR r.deleted_at IS NOT NULL) AS borrado,
         t.nombre, t.id AS torneo_id,
         r.rating_inicio, r.rating_fin, r.ganados, r.perdidos, r.id AS orden
  FROM public.resultados_evento r
  JOIN public.torneos t ON t.id = r.id_torneo
  WHERE r.id_jugador = (SELECT id FROM p)
),
-- El salto se mide solo entre torneos vigentes: borrar un torneo ya
-- devuelve el rating al de antes, así que no cuenta como eslabón.
vigentes AS (
  SELECT orden,
         rating_inicio - LAG(rating_fin) OVER (ORDER BY cuando, orden) AS salto
  FROM torneos_jugador
  WHERE NOT borrado
),
linea AS (
  SELECT tj.cuando, 'torneo' AS tipo,
         tj.nombre || CASE WHEN tj.borrado THEN ' (BORRADO)' ELSE '' END AS detalle,
         tj.torneo_id, tj.rating_inicio, tj.rating_fin, tj.ganados, tj.perdidos,
         v.salto, tj.orden
  FROM torneos_jugador tj
  LEFT JOIN vigentes v ON v.orden = tj.orden

  UNION ALL
  -- Borradores (pendientes o publicados) donde aparece: con qué rating lo
  -- tomó el sitio al procesar el CSV.
  SELECT d.created_at, 'borrador ' || COALESCE(d.status, ''), d.torneo_nombre,
         NULL, round((s->>'rating_inicio')::numeric)::int,
         round((s->>'rating_fin')::numeric)::int,
         (s->>'ganados')::int, (s->>'perdidos')::int, NULL, NULL
  FROM public.resultados_draft d
  CROSS JOIN LATERAL jsonb_array_elements(d.snapshot_map) s
  WHERE (s->>'id_jugador')::bigint = (SELECT id FROM p)

  UNION ALL
  SELECT now(), 'RATING ACTUAL', b."First Name" || ' ' || b."Last Name",
         NULL, NULL, round(b."New Rating"::numeric)::int, NULL, NULL, NULL, NULL
  FROM public."Base de Datos" b
  WHERE b."Member ID" = (SELECT id FROM p)
)
SELECT cuando::date AS fecha, tipo, detalle, torneo_id,
       rating_inicio, rating_fin, ganados, perdidos, salto
FROM linea
ORDER BY cuando, orden NULLS LAST;


-- ---------------------------------------------------------------------------
-- CONSULTA 2 · Cada vez que alguien cambió su "New Rating", con fecha y hora
--
-- Necesita la tabla audit_log (sql/create_audit_log.sql). Si da error
-- "relation audit_log does not exist", ese registro no estaba activo:
-- sáltala y usa solo la consulta 1.
-- ---------------------------------------------------------------------------
WITH p AS (SELECT 51245 AS id)
SELECT a.occurred_at AT TIME ZONE 'America/Puerto_Rico' AS cuando_pr,
       a.action,
       a.actor,
       (a.old_data->>'New Rating') AS antes,
       (a.new_data->>'New Rating') AS despues
FROM public.audit_log a
WHERE a.table_name = 'Base de Datos'
  AND a.record_id  = (SELECT id FROM p)::text
  AND (a.old_data->>'New Rating') IS DISTINCT FROM (a.new_data->>'New Rating')
ORDER BY a.occurred_at;
