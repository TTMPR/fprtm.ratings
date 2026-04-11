-- =============================================================================
-- Fix: políticas de escritura faltantes en "Base de Datos"
-- RLS fue activado pero solo existe la política de SELECT (allow_public_read).
-- Sin estas políticas, INSERT y UPDATE fallan aunque el admin esté logueado.
-- Corre esto en el SQL Editor de Supabase.
-- =============================================================================

-- Hacer nullable todas las columnas opcionales.
-- Member ID y Date of Birth son PK y deben mantenerse NOT NULL.
-- Las demás columnas son opcionales en el flujo de creación desde el app.
DO $$
DECLARE
  col text;
BEGIN
  FOR col IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'Base de Datos'
      AND is_nullable  = 'NO'
      AND column_name NOT IN ('Member ID', 'Date of Birth')
  LOOP
    EXECUTE format(
      'ALTER TABLE public."Base de Datos" ALTER COLUMN %I DROP NOT NULL',
      col
    );
    RAISE NOTICE 'Dropped NOT NULL on column: %', col;
  END LOOP;
END $$;

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
