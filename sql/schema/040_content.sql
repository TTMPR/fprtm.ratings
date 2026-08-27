-- ============================================================================
-- 040 · Configuración, contenido y clubes
--
-- Sin dependencias sobre las tablas núcleo.
--
-- Origen (curado):
--   create_app_settings.sql + fix_app_settings_enable_rls.sql
--   create_articulos.sql
--   create_clubs_table.sql (SÓLO la tabla y sus políticas)
--
-- Las partes de Storage de create_clubs_table.sql viven en 100_storage.sql:
-- el esquema storage sólo existe en Supabase, y separarlas permite validar
-- este fichero en un Postgres normal.
-- ============================================================================

-- ────────── app_settings ──────────
-- ══════════════════════════════════════════
-- APP SETTINGS TABLE
-- Run once in Supabase SQL Editor
-- ══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.app_settings (
  key        text PRIMARY KEY,
  value      text NOT NULL,
  updated_at timestamptz DEFAULT now()
);

-- Allow anyone to read settings (needed for inscription status check)
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Las políticas de app_settings se definen una sola vez, más abajo, en la
-- versión de fix_app_settings_enable_rls.sql (idéntica pero con DROP previo,
-- así el fichero es re-ejecutable). El create_app_settings.sql original las
-- declaraba aquí sin DROP, lo que impedía re-aplicarlo.

-- Seed default: inscriptions open
INSERT INTO public.app_settings (key, value)
VALUES ('inscripciones_open', 'true')
ON CONFLICT (key) DO NOTHING;

-- Estado final de RLS tras fix_app_settings_enable_rls.sql (idempotente)
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_app_settings"          ON public.app_settings;
DROP POLICY IF EXISTS "authenticated_write_app_settings"  ON public.app_settings;
CREATE POLICY "public_read_app_settings"
  ON public.app_settings FOR SELECT
  TO anon, authenticated
  USING (true);
DROP POLICY IF EXISTS "authenticated_write_app_settings" ON public.app_settings;
CREATE POLICY "authenticated_write_app_settings"
  ON public.app_settings FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);


-- ────────── articulos ──────────
-- ============================================================
--  FPTM — Tabla de artículos (blog / noticias)
--  Ejecutar en: Supabase → SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS public.articulos (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  titulo      TEXT        NOT NULL,
  resumen     TEXT,
  contenido   TEXT        NOT NULL,
  imagen_url  TEXT,
  autor       TEXT        DEFAULT 'FPTM',
  publicado   BOOLEAN     DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.articulos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can read published articulos" ON public.articulos;
CREATE POLICY "Public can read published articulos"
  ON public.articulos FOR SELECT TO anon, authenticated
  USING (publicado = true);

DROP POLICY IF EXISTS "Authenticated can manage articulos" ON public.articulos;
CREATE POLICY "Authenticated can manage articulos"
  ON public.articulos FOR ALL TO authenticated
  USING (true) WITH CHECK (true);


-- ────────── clubs (sin Storage) ──────────
-- ============================================================
--  FPTM — Tabla de clubes (logos y descripción)
--  Ejecutar en: Supabase → SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS public.clubs (
  name        TEXT PRIMARY KEY,
  logo_url    TEXT,
  descripcion TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can read clubs" ON public.clubs;
CREATE POLICY "Public can read clubs"
  ON public.clubs FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated can manage clubs" ON public.clubs;
CREATE POLICY "Authenticated can manage clubs"
  ON public.clubs FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- El bucket club-logos y sus políticas de storage viven en 100_storage.sql.


-- ────────── club_info_requests (agrupado con clubs: depende de esa tabla) ──────────
-- ────────── create_club_info_requests.sql ──────────
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

