-- Add payment reference code column to insc_registro
-- Run this in the Supabase SQL Editor.

ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS referencia TEXT;
