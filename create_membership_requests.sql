-- ============================================================
-- TABLA: membership_requests
-- Solicitudes de membresía (nuevas y renovaciones)
-- Ejecutar en Supabase SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS membership_requests (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  type               TEXT NOT NULL DEFAULT 'new',           -- 'new' | 'renewal'
  existing_player_id INTEGER,                               -- nullable; solo si type='renewal'
  first_name         TEXT NOT NULL,
  last_name          TEXT NOT NULL,
  email              TEXT,
  phone              TEXT,
  dob                DATE,
  sex                TEXT CHECK (sex IN ('M', 'F')),
  club               TEXT,
  address            TEXT,
  city               TEXT,
  state              TEXT,
  country            TEXT DEFAULT 'Puerto Rico',
  zipcode            TEXT,
  is_minor           BOOLEAN DEFAULT FALSE,
  guardian_name      TEXT,
  guardian_relation  TEXT,
  ath_confirmation   TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'approved', 'rejected')),
  notes              TEXT,
  created_at         TIMESTAMPTZ DEFAULT NOW(),
  processed_at       TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE membership_requests ENABLE ROW LEVEL SECURITY;

-- Anyone (including anonymous visitors) can submit a request
CREATE POLICY "Public can submit membership requests"
  ON membership_requests FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Only authenticated users (admin) can read requests
CREATE POLICY "Admin can view membership requests"
  ON membership_requests FOR SELECT
  TO authenticated
  USING (true);

-- Only authenticated users can update status (approve/reject)
CREATE POLICY "Admin can process membership requests"
  ON membership_requests FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
