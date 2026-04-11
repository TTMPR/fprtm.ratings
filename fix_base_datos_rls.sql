-- =============================================================================
-- Fix: políticas de escritura faltantes en "Base de Datos"
-- RLS fue activado pero solo existe la política de SELECT (allow_public_read).
-- Sin estas políticas, INSERT y UPDATE fallan aunque el admin esté logueado.
-- Corre esto en el SQL Editor de Supabase.
-- =============================================================================

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
