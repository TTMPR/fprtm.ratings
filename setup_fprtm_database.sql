-- =============================================================================
-- FPTM — Database Setup
-- Run this entire file in the Supabase SQL Editor (Dashboard → SQL Editor).
-- It is safe to re-run: all statements use IF NOT EXISTS / IF EXISTS guards.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- TABLE: membership_requests
-- Solicitudes de membresía (nuevas y renovaciones)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.membership_requests (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  type               TEXT NOT NULL DEFAULT 'new',
  existing_player_id INTEGER,
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

ALTER TABLE public.membership_requests ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'membership_requests' AND policyname = 'Public can submit membership requests'
  ) THEN
    CREATE POLICY "Public can submit membership requests"
      ON public.membership_requests FOR INSERT
      TO anon, authenticated
      WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'membership_requests' AND policyname = 'Admin can view membership requests'
  ) THEN
    CREATE POLICY "Admin can view membership requests"
      ON public.membership_requests FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'membership_requests' AND policyname = 'Admin can process membership requests'
  ) THEN
    CREATE POLICY "Admin can process membership requests"
      ON public.membership_requests FOR UPDATE
      TO authenticated
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;


-- ---------------------------------------------------------------------------
-- TABLE: photo_requests
-- Solicitudes de foto de jugador
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.photo_requests (
  id         BIGSERIAL    PRIMARY KEY,
  member_id  INT          NOT NULL,
  photo_url  TEXT         NOT NULL,
  status     TEXT         NOT NULL DEFAULT 'pending',
  is_minor   BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ  DEFAULT NOW()
);

COMMENT ON COLUMN public.photo_requests.is_minor IS
  'TRUE si el jugador es menor de 18 años. Indica que se requirió y confirmó autorización del tutor legal antes de subir la foto.';

CREATE INDEX IF NOT EXISTS idx_photo_requests_member ON public.photo_requests (member_id);
CREATE INDEX IF NOT EXISTS idx_photo_requests_status ON public.photo_requests (status);

ALTER TABLE public.photo_requests ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'photo_requests' AND policyname = 'photo_public_read'
  ) THEN
    CREATE POLICY "photo_public_read"
      ON public.photo_requests FOR SELECT
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'photo_requests' AND policyname = 'photo_anon_insert'
  ) THEN
    CREATE POLICY "photo_anon_insert"
      ON public.photo_requests FOR INSERT
      WITH CHECK (status = 'pending');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'photo_requests' AND policyname = 'photo_admin_update'
  ) THEN
    CREATE POLICY "photo_admin_update"
      ON public.photo_requests FOR UPDATE
      TO authenticated
      WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');
  END IF;
END $$;


-- ---------------------------------------------------------------------------
-- TABLE: club_change_requests
-- Solicitudes de cambio de club
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.club_change_requests (
  id           BIGSERIAL PRIMARY KEY,
  member_id    INTEGER   NOT NULL,
  current_club TEXT,
  new_club     TEXT      NOT NULL,
  status       TEXT      NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.club_change_requests ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'club_change_requests' AND policyname = 'club_req_insert_public'
  ) THEN
    CREATE POLICY "club_req_insert_public"
      ON public.club_change_requests FOR INSERT
      TO public
      WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'club_change_requests' AND policyname = 'club_req_select_public'
  ) THEN
    CREATE POLICY "club_req_select_public"
      ON public.club_change_requests FOR SELECT
      TO public
      USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'club_change_requests' AND policyname = 'club_req_update_admin'
  ) THEN
    CREATE POLICY "club_req_update_admin"
      ON public.club_change_requests FOR UPDATE
      TO authenticated
      USING (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz')
      WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');
  END IF;
END $$;


-- ---------------------------------------------------------------------------
-- SECURITY FIXES for existing tables
-- ---------------------------------------------------------------------------

-- 1. Enable RLS on "Base de Datos"
ALTER TABLE public."Base de Datos" ENABLE ROW LEVEL SECURITY;

-- 2. Fix SECURITY DEFINER view: miembros_alertas
ALTER VIEW public.miembros_alertas SET (security_invoker = on);

-- 3. Pin search_path on update_updated_at
ALTER FUNCTION public.update_updated_at()
  SET search_path = '';

-- 4. Restrict INSERT on partidos to admin only
DROP POLICY IF EXISTS "insert_partidos" ON public.partidos;
CREATE POLICY "insert_partidos" ON public.partidos
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

-- 5. Restrict INSERT on torneos to admin only
DROP POLICY IF EXISTS "insert_torneos" ON public.torneos;
CREATE POLICY "insert_torneos" ON public.torneos
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');


-- ---------------------------------------------------------------------------
-- TABLE: app_settings
-- Key-value store for global app configuration (e.g. inscripciones toggle)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Seed default: inscripciones open
INSERT INTO public.app_settings (key, value)
  VALUES ('inscripciones_open', 'true')
  ON CONFLICT (key) DO NOTHING;

-- RLS: anyone can read, only admin can write
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read_app_settings" ON public.app_settings;
CREATE POLICY "read_app_settings" ON public.app_settings
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "write_app_settings" ON public.app_settings;
CREATE POLICY "write_app_settings" ON public.app_settings
  FOR ALL TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

-- =============================================================================
-- NOTE: After running this script, complete these manual steps in the Dashboard:
--
--   1. Authentication → Providers → Email → Enable "Leaked Password Protection"
--
--   2. Storage → Create a bucket named: player-photos
--      - Mark as Public bucket
--      - Add INSERT policy for anon role with definition: true
-- =============================================================================
