-- Allow public (anon) to read insc_registro so the player list is visible to everyone.
-- The existing admin_select_insc_registro policy stays — this adds public read on top.
-- Run this in the Supabase SQL Editor.

DROP POLICY IF EXISTS "public_select_insc_registro" ON public.insc_registro;
CREATE POLICY "public_select_insc_registro"
  ON public.insc_registro FOR SELECT TO anon
  USING (true);
