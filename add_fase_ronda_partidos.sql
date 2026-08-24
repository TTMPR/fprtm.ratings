-- ============================================================
--  FPTM — Fase, ronda, grupo y marcador por partido
--  Ejecutar en: Supabase → SQL Editor ANTES de subir resultados
--
--  Datos que ya vienen en el CSV de Stadium y que hasta ahora se
--  descartaban. Sin ellos no se pueden reconstruir las tablas de
--  grupos ni las llaves de un torneo pasado.
-- ============================================================

-- "grupos" | "llave" | "roundrobin"  (de la columna drawName)
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS fase TEXT;

-- "Final", "Semifinal", "Round of 16"…  (de description, sin el #n)
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS ronda TEXT;

-- "1", "2", "3"…  sólo en fase de grupos (de "Group 2 (A vs. B)")
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS grupo TEXT;

-- Marcador por juego en notación estándar: "9,-6,-6,4,5"
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS marcador TEXT;

-- Orden dentro de la ronda, para dibujar la llave: "Quarterfinal #3" → 3
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS orden INTEGER;

-- Consultar por torneo + categoría es la operación central de la vista
CREATE INDEX IF NOT EXISTS idx_partidos_torneo_categoria
  ON public.partidos (torneo_id, categoria);

-- Verificar
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'partidos'
  AND column_name IN ('categoria','fase','ronda','grupo','marcador','orden')
ORDER BY column_name;
