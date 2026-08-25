-- ============================================================
--  FPTM — Modo borrador para torneos (publish / unpublish)
--  Ejecutar en: Supabase → SQL Editor
--
--  Un torneo en borrador lo ve solo el admin: no aparece en la
--  lista de Torneos ni sus partidos en los perfiles de jugadores.
--  Sirve para revisar grupos, llaves y resultados antes de que el
--  público los vea.
--
--  Nota: los ratings se aplican en el paso "Publicar Ratings" y son
--  independientes de esta bandera.
-- ============================================================

ALTER TABLE public.torneos            ADD COLUMN IF NOT EXISTS publicado BOOLEAN DEFAULT true;
ALTER TABLE public.partidos           ADD COLUMN IF NOT EXISTS publicado BOOLEAN DEFAULT true;
ALTER TABLE public.resultados_evento  ADD COLUMN IF NOT EXISTS publicado BOOLEAN DEFAULT true;

-- Todo lo que ya existe queda público (era visible hasta ahora)
UPDATE public.torneos           SET publicado = true WHERE publicado IS NULL;
UPDATE public.partidos          SET publicado = true WHERE publicado IS NULL;
UPDATE public.resultados_evento SET publicado = true WHERE publicado IS NULL;

-- El público filtra por esta columna en cada consulta
CREATE INDEX IF NOT EXISTS torneos_publicado_idx
  ON public.torneos (publicado);
CREATE INDEX IF NOT EXISTS partidos_publicado_idx
  ON public.partidos (publicado);
CREATE INDEX IF NOT EXISTS resultados_evento_publicado_idx
  ON public.resultados_evento (publicado);

-- Verificar
SELECT t.nombre, t.fecha, t.publicado,
       (SELECT count(*) FROM partidos p WHERE p.torneo_id = t.id) AS partidos
FROM public.torneos t
ORDER BY t.fecha DESC
LIMIT 15;
