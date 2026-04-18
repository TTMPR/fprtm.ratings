-- Add club column to insc_registro so players can confirm/update their club
-- during the inscription process.
-- Run in Supabase SQL Editor.

ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS club TEXT;
