-- ============================================================================
-- 000 · Extensiones
--
-- Verificado contra producción (extracción 2026-09-03). Producción tiene:
--   pg_cron 1.6.4          job de purga de la papelera (ver 070)
--   pgcrypto 1.3           gen_random_uuid() — default de jugadores.id
--   uuid-ossp 1.1          histórico; no lo usa ninguna tabla del esquema
--   pg_stat_statements     lo instala Supabase
--   supabase_vault         lo instala Supabase
--   plpgsql                built-in
--
-- Aquí sólo se declaran las que el esquema de la aplicación necesita.
-- Supabase provee las suyas: no hace falta declararlas.
-- ============================================================================

-- Purga programada de torneos en la papelera. En Supabase se habilita también
-- desde Database → Extensions. En un Postgres local sin el paquete pg_cron
-- esta línea falla — es esperado y no bloquea el resto (ver README.md).
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- gen_random_uuid() para jugadores.id. En PostgreSQL 13+ la función es
-- built-in, pero producción tiene pgcrypto instalado; se declara para que
-- staging coincida.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
