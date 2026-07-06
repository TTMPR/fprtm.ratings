-- ============================================================
--  FPTM — Tabla de clubes (logos y descripción)
--  Ejecutar en: Supabase → SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS public.clubs (
  name        TEXT PRIMARY KEY,
  logo_url    TEXT,
  descripcion TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read clubs"
  ON public.clubs FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "Authenticated can manage clubs"
  ON public.clubs FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Storage bucket para logos (ejecutar también)
INSERT INTO storage.buckets (id, name, public)
VALUES ('club-logos', 'club-logos', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY IF NOT EXISTS "Public read club-logos"
  ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'club-logos');

CREATE POLICY IF NOT EXISTS "Authenticated upload club-logos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'club-logos');

CREATE POLICY IF NOT EXISTS "Authenticated update club-logos"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'club-logos');
