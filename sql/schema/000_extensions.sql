-- ============================================================================
-- 000 · Extensiones
--
-- Origen: sql/soft_delete_torneos.sql (única extensión declarada en el repo).
-- ============================================================================

-- pg_cron: purga programada de torneos en la papelera (ver 070).
-- En Supabase se habilita desde Database → Extensions; el CREATE EXTENSION
-- funciona igual desde el SQL Editor.
-- En un Postgres local sin el paquete pg_cron, esta línea falla: es esperado
-- y no bloquea el resto del esquema (ver sql/schema/README.md).
CREATE EXTENSION IF NOT EXISTS pg_cron;
