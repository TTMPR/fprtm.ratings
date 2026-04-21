-- Add pagado column to track payment confirmation per inscription.
-- Admin toggles this from the Gestionar Inscritos panel.
-- Run in Supabase SQL Editor.

ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS pagado BOOLEAN DEFAULT FALSE;
