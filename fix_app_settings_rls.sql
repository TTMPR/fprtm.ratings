-- Fix: deshabilitar RLS en app_settings para que la anon key pueda escribir
-- (consistente con el resto de las tablas del app)
-- Corre esto en el SQL Editor de Supabase

ALTER TABLE public.app_settings DISABLE ROW LEVEL SECURITY;
