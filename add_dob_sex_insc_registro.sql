-- Add date-of-birth and sex columns to insc_registro
-- These are captured at registration time for category validation records.
-- Run this in the Supabase SQL Editor.

ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS dob  TEXT,
  ADD COLUMN IF NOT EXISTS sex  TEXT;
