-- ============================================================
--  FPTM — Patch: logo proposals in club_info_requests
--  Ejecutar en: Supabase → SQL Editor
-- ============================================================

-- 1. Add logo_url column to club_info_requests
ALTER TABLE public.club_info_requests ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- 2. Allow anonymous users to upload to pending/ prefix in club-logos bucket
DROP POLICY IF EXISTS "Public upload pending club logos" ON storage.objects;
CREATE POLICY "Public upload pending club logos"
  ON storage.objects FOR INSERT TO anon
  WITH CHECK (bucket_id = 'club-logos' AND name LIKE 'pending/%');
