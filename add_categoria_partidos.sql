-- ============================================================
--  FPTM — Categoría por partido y por borrador de resultados
--  Ejecutar en: Supabase → SQL Editor ANTES de subir resultados
--
--  Sin estas columnas, publicar un torneo falla: la app guarda la
--  categoría de cada partido para poder mostrar victorias y derrotas
--  agrupadas por categoría en el perfil del jugador.
-- ============================================================

-- Categoría del partido (ej. "1800 Under", "13U Masculino")
ALTER TABLE public.partidos
  ADD COLUMN IF NOT EXISTS categoria TEXT;

-- Categoría del lote que está pendiente de publicar
ALTER TABLE public.resultados_draft
  ADD COLUMN IF NOT EXISTS torneo_categoria TEXT;

-- Verificar
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE (table_name = 'partidos'          AND column_name IN ('categoria', 'categoria_evento'))
   OR (table_name = 'resultados_draft'  AND column_name = 'torneo_categoria')
ORDER BY table_name, column_name;
