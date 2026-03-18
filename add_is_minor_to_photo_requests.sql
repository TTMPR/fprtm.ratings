-- Migration: Add is_minor field to photo_requests table
-- Purpose: Track whether a photo is of a minor (under 18) to enforce
--          parental/guardian consent disclosure requirements.
--
-- Run this in the Supabase SQL Editor.

ALTER TABLE photo_requests
  ADD COLUMN IF NOT EXISTS is_minor BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN photo_requests.is_minor IS
  'TRUE si el jugador es menor de 18 años. Indica que se requirió y confirmó autorización del tutor legal antes de subir la foto.';
