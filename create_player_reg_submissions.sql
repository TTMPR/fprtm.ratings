-- Non-member registration submissions
-- Submitted by players via the shareable registration link.
-- Admin reviews, approves, and adds to Base de Datos.
-- Run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.player_reg_submissions (
  id                BIGSERIAL PRIMARY KEY,
  token             TEXT REFERENCES public.player_reg_tokens(token),
  nombre            TEXT NOT NULL,
  apellidos         TEXT NOT NULL,
  email             TEXT,
  telefono          TEXT,
  dob               TEXT,
  sex               TEXT,
  club              TEXT,
  address           TEXT,
  city              TEXT,
  state             TEXT,
  zip               TEXT,
  country           TEXT DEFAULT 'Puerto Rico',
  is_minor          BOOLEAN DEFAULT FALSE,
  guardian_name     TEXT,
  guardian_relation TEXT,
  status            TEXT DEFAULT 'pending',   -- pending | approved | rejected
  admin_notes       TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  approved_at       TIMESTAMPTZ,
  approved_member_id INTEGER                  -- filled when approved
);

ALTER TABLE public.player_reg_submissions ENABLE ROW LEVEL SECURITY;

-- Public: can submit (INSERT only)
CREATE POLICY "anon_insert_reg_submissions"
  ON public.player_reg_submissions FOR INSERT TO anon
  WITH CHECK (true);

-- Admin: full access
CREATE POLICY "admin_all_reg_submissions"
  ON public.player_reg_submissions FOR ALL TO authenticated
  USING (true) WITH CHECK (true);
