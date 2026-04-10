-- ══════════════════════════════════════════
-- APP SETTINGS TABLE
-- Run once in Supabase SQL Editor
-- ══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.app_settings (
  key        text PRIMARY KEY,
  value      text NOT NULL,
  updated_at timestamptz DEFAULT now()
);

-- Allow anyone to read settings (needed for inscription status check)
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_app_settings"
  ON public.app_settings FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "authenticated_write_app_settings"
  ON public.app_settings FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Seed default: inscriptions open
INSERT INTO public.app_settings (key, value)
VALUES ('inscripciones_open', 'true')
ON CONFLICT (key) DO NOTHING;
