-- Non-member registration tokens
-- Each token is a one-time-use link the admin generates and sends to a player.
-- Run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.player_reg_tokens (
  token       TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  label       TEXT,           -- admin note, e.g. "Para: Juan Pérez"
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  used        BOOLEAN DEFAULT FALSE,
  used_at     TIMESTAMPTZ
);

ALTER TABLE public.player_reg_tokens ENABLE ROW LEVEL SECURITY;

-- Admin: full access
CREATE POLICY "admin_all_reg_tokens"
  ON public.player_reg_tokens FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- Public: can read to validate a token
CREATE POLICY "anon_read_reg_tokens"
  ON public.player_reg_tokens FOR SELECT TO anon
  USING (true);

-- Public: can mark an unused token as used (when submitting the form)
CREATE POLICY "anon_use_reg_token"
  ON public.player_reg_tokens FOR UPDATE TO anon
  USING (used = false)
  WITH CHECK (used = true);
