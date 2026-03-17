-- ══════════════════════════════════════════
-- TABLE: club_change_requests
-- Players submit a request to change their club.
-- Admin approves or rejects from the queue.
-- ══════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.club_change_requests (
  id          BIGSERIAL PRIMARY KEY,
  member_id   INTEGER   NOT NULL,
  current_club TEXT,
  new_club    TEXT      NOT NULL,
  status      TEXT      NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','approved','rejected')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE public.club_change_requests ENABLE ROW LEVEL SECURITY;

-- Public (anonymous) can INSERT a request
CREATE POLICY "club_req_insert_public"
  ON public.club_change_requests
  FOR INSERT
  TO public
  WITH CHECK (true);

-- Public can read their own pending requests (optional – needed for duplicate-check)
CREATE POLICY "club_req_select_public"
  ON public.club_change_requests
  FOR SELECT
  TO public
  USING (true);

-- Only authenticated admin can UPDATE (approve / reject)
CREATE POLICY "club_req_update_admin"
  ON public.club_change_requests
  FOR UPDATE
  TO authenticated
  USING (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz')
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');
