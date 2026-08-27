-- ============================================================================
-- 100 · Storage (SÓLO Supabase)
--
-- Este fichero NO se puede aplicar en un Postgres normal: el esquema
-- `storage` lo crea Supabase. Por eso está separado de 050.
--
-- Origen: create_clubs_table.sql (parte de Storage) + los buckets que la
-- aplicación usa según index.html.
--
-- Buckets referenciados por la aplicación:
--   club-logos     público   logos de club
--   player-photos  público   fotos de jugador
--   backups        PRIVADO   destino del backup semanal (lo crea
--                            backup/export_backup.mjs, no este fichero)
-- ============================================================================

-- Storage bucket para logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('club-logos', 'club-logos', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public read club-logos" ON storage.objects;
CREATE POLICY "Public read club-logos"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'club-logos');

DROP POLICY IF EXISTS "Authenticated upload club-logos" ON storage.objects;
CREATE POLICY "Authenticated upload club-logos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'club-logos');

DROP POLICY IF EXISTS "Authenticated update club-logos" ON storage.objects;
CREATE POLICY "Authenticated update club-logos"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'club-logos');


-- ── player-photos ───────────────────────────────────────────────────────────
-- ⚠ NO hay fichero en el repositorio que cree este bucket ni sus políticas.
--   La app sube y lee de él (index.html: showPhotoUploadModal,
--   showPendingPhotosModal). Recuperar su configuración real de producción
--   antes de crear staging — ver docs/STAGING_RUNBOOK.md.
