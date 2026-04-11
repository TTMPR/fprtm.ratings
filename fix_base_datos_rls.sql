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
    SELECT c.column_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name   = 'Base de Datos'
      AND c.is_nullable  = 'NO'
      AND c.column_name NOT IN (
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema    = kcu.table_schema
        WHERE tc.table_schema    = 'public'
          AND tc.table_name      = 'Base de Datos'
          AND tc.constraint_type = 'PRIMARY KEY'
      )
  LOOP
    EXECUTE format(
      'ALTER TABLE public."Base de Datos" ALTER COLUMN %I DROP NOT NULL',
      col
    );
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
