-- Staging table for tournament results before publishing to Base de Datos.
-- Admin uploads CSV → results saved here → admin reviews → publishes.
-- Run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.resultados_draft (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  torneo_nombre TEXT        NOT NULL,
  torneo_fecha  DATE        NOT NULL,
  partidos      JSONB       NOT NULL,
  snapshot_map  JSONB       NOT NULL,
  col_name      TEXT,       -- e.g. "rating_morovis_open_2026"
  status        TEXT        DEFAULT 'pending',
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  published_at  TIMESTAMPTZ
);

-- Allow admins (authenticated) to do everything
ALTER TABLE public.resultados_draft ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can manage drafts"
  ON public.resultados_draft
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
