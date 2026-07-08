-- ============================================================
--  FPTM — Patch: propuestas de logo en club_info_requests
--  Ejecutar en: Supabase → SQL Editor
--
--  Nota: ya NO se necesita ninguna política de storage para el
--  público. Las propuestas viajan como data URL (base64) dentro
--  de club_info_requests; al aprobar, la sesión del admin sube
--  el archivo al bucket club-logos con las políticas existentes.
-- ============================================================

-- Columna para la imagen propuesta (data URL) o URL final
ALTER TABLE public.club_info_requests ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- Verificar: debe listar logo_url entre las columnas
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'club_info_requests'
ORDER BY ordinal_position;
