-- Fix security vulnerability: re-enable RLS on app_settings.
-- The table already has the correct policies:
--   public_read_app_settings     → anon can SELECT (needed to check inscripciones_open)
--   authenticated_write_app_settings → only logged-in admin can INSERT/UPDATE/DELETE
--
-- The app code has been updated to use the authenticated Supabase client
-- for writes, so disabling RLS is no longer needed.
--
-- Run this in the Supabase SQL Editor.

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Re-create policies cleanly (safe to run even if they already exist)
DROP POLICY IF EXISTS "public_read_app_settings"          ON public.app_settings;
DROP POLICY IF EXISTS "authenticated_write_app_settings"  ON public.app_settings;

CREATE POLICY "public_read_app_settings"
  ON public.app_settings FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "authenticated_write_app_settings"
  ON public.app_settings FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
