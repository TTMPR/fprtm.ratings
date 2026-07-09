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
