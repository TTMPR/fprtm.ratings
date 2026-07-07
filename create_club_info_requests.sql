-- ============================================================
--  FPTM — Club info: columnas adicionales + tabla de solicitudes
--  Ejecutar en: Supabase → SQL Editor
-- ============================================================

-- 1. Agregar columnas de contacto a la tabla clubs (si no existen)
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS descripcion TEXT;
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS direccion   TEXT;
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS telefono    TEXT;
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS encargado   TEXT;

-- 2. Tabla de solicitudes de actualización de info de clubes
CREATE TABLE IF NOT EXISTS public.club_info_requests (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  club_name    TEXT        NOT NULL,
  solicitante  TEXT,
  direccion    TEXT,
  telefono     TEXT,
  encargado    TEXT,
  descripcion  TEXT,
  status       TEXT        DEFAULT 'pending',
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  reviewed_at  TIMESTAMPTZ
);

ALTER TABLE public.club_info_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can submit club_info_requests" ON public.club_info_requests;
CREATE POLICY "Public can submit club_info_requests"
  ON public.club_info_requests FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Public can view club_info_requests" ON public.club_info_requests;
CREATE POLICY "Public can view club_info_requests"
  ON public.club_info_requests FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "Authenticated can manage club_info_requests" ON public.club_info_requests;
CREATE POLICY "Authenticated can manage club_info_requests"
  ON public.club_info_requests FOR ALL TO authenticated USING (true) WITH CHECK (true);
