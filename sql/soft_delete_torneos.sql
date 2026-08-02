-- =============================================================================
-- FPTM · Fase 3.5 — Soft delete para "Borrar Torneo"
--
-- ⚠️  REVISAR ANTES DE APLICAR. Correr en el Supabase SQL Editor.
--     Es aditivo: agrega columnas nullable y una función de purga.
--     APLICAR ANTES de mergear el branch de la app que usa deleted_at
--     (la app detecta si la columna existe y hace fallback al borrado
--     duro si no, así que el orden inverso tampoco rompe nada — pero
--     sin este SQL el soft delete simplemente no se activa).
--
-- Qué hace:
--   1. Agrega deleted_at a torneos, resultados_evento y partidos.
--   2. "Borrar Torneo" en la app pasa a marcar deleted_at (papelera)
--      en vez de DELETE. "No se puede deshacer" → "30 días para deshacer".
--   3. Función de purga que borra de verdad lo que lleve >30 días en la
--      papelera + schedule con pg_cron.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Columnas deleted_at (nullable → las filas existentes quedan "vivas")
-- ---------------------------------------------------------------------------
ALTER TABLE public.torneos            ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE public.resultados_evento  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE public.partidos           ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

-- Índices parciales: las consultas de la papelera solo miran filas borradas
CREATE INDEX IF NOT EXISTS torneos_deleted_at_idx
  ON public.torneos (deleted_at) WHERE deleted_at IS NOT NULL;


-- ---------------------------------------------------------------------------
-- 2. Purga: borra definitivamente lo que lleve más de 30 días en papelera.
--    El orden respeta la relación lógica (hijos primero).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_deleted_torneos() RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  purged integer := 0;
BEGIN
  DELETE FROM public.partidos
    WHERE deleted_at IS NOT NULL AND deleted_at < now() - interval '30 days';

  DELETE FROM public.resultados_evento
    WHERE deleted_at IS NOT NULL AND deleted_at < now() - interval '30 days';

  WITH gone AS (
    DELETE FROM public.torneos
      WHERE deleted_at IS NOT NULL AND deleted_at < now() - interval '30 days'
      RETURNING 1
  )
  SELECT count(*) INTO purged FROM gone;

  RETURN purged;
END;
$$;

-- La función corre como owner (SECURITY DEFINER); que la API no pueda llamarla:
REVOKE EXECUTE ON FUNCTION public.purge_deleted_torneos() FROM anon, authenticated;


-- ---------------------------------------------------------------------------
-- 3. Job diario con pg_cron (3:30 AM UTC). En Supabase: Database → Extensions
--    → habilitar pg_cron si no lo está, y luego correr:
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Re-ejecutable: quita el job previo si existe
SELECT cron.unschedule('purge-deleted-torneos')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-deleted-torneos');

SELECT cron.schedule(
  'purge-deleted-torneos',
  '30 3 * * *',
  $$SELECT public.purge_deleted_torneos()$$
);


-- Verificación rápida tras aplicar:
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name IN ('torneos','resultados_evento','partidos')
--     AND column_name = 'deleted_at';
-- SELECT jobname, schedule FROM cron.job WHERE jobname = 'purge-deleted-torneos';
