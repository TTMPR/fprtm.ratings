-- =============================================================================
-- Fix: políticas de escritura faltantes en "Base de Datos"
-- RLS fue activado pero solo existe la política de SELECT (allow_public_read).
-- Sin estas políticas, INSERT y UPDATE fallan aunque el admin esté logueado.
-- Corre esto en el SQL Editor de Supabase.
-- =============================================================================

-- "Date of Birth" tiene NOT NULL pero no siempre está disponible al crear
-- un jugador desde una solicitud de membresía o manualmente.
ALTER TABLE public."Base de Datos"
  ALTER COLUMN "Date of Birth" DROP NOT NULL;

-- Permitir al admin insertar nuevos jugadores
DROP POLICY IF EXISTS "admin_insert_base_datos" ON public."Base de Datos";
CREATE POLICY "admin_insert_base_datos"
  ON public."Base de Datos"
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

-- Permitir al admin actualizar jugadores existentes
DROP POLICY IF EXISTS "admin_update_base_datos" ON public."Base de Datos";
CREATE POLICY "admin_update_base_datos"
  ON public."Base de Datos"
  FOR UPDATE
  TO authenticated
  USING  (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz')
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');
