-- ============================================================
-- FPTM — Tabla photo_requests
-- Ejecutar en Supabase → SQL Editor antes de usar fotos
-- ============================================================

CREATE TABLE IF NOT EXISTS photo_requests (
  id         BIGSERIAL    PRIMARY KEY,
  member_id  INT          NOT NULL,
  photo_url  TEXT         NOT NULL,
  status     TEXT         NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_photo_requests_member ON photo_requests (member_id);
CREATE INDEX IF NOT EXISTS idx_photo_requests_status ON photo_requests (status);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE photo_requests ENABLE ROW LEVEL SECURITY;

-- Lectura pública (admin necesita ver pending, app necesita approved)
CREATE POLICY "photo_public_read"
  ON photo_requests FOR SELECT
  USING (true);

-- Cualquiera puede enviar una solicitud pendiente
CREATE POLICY "photo_anon_insert"
  ON photo_requests FOR INSERT
  WITH CHECK (status = 'pending');

-- Solo el admin puede aprobar / rechazar
CREATE POLICY "photo_admin_update"
  ON photo_requests FOR UPDATE
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

-- ── Storage bucket ───────────────────────────────────────────
-- Paso manual en Supabase Dashboard → Storage:
--   1. Crear bucket llamado: player-photos
--   2. Marcar como Public bucket
--   3. En Policies del bucket, crear política:
--        Operation: INSERT
--        Role:      anon
--        Definition: true
-- ─────────────────────────────────────────────────────────────
