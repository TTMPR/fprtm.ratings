-- ============================================================================
-- 050 · Membresías, fotos, clubes de jugador y registro de jugadores
--
-- Depende de: 010 ("Base de Datos").
--
-- Origen (curado, en orden de dependencia):
--   setup_fprtm_database.sql        membership_requests, photo_requests, club_change_requests
--   create_membership_requests.sql  variante posterior de la misma tabla
--   create_photo_requests.sql
--   club_change_requests.sql
--   add_is_minor_to_photo_requests.sql
--   create_club_info_requests.sql
--   create_player_reg_tokens.sql    (antes que submissions: hay FK)
--   create_player_reg_submissions.sql
--   create_resultados_draft.sql
--
-- ⚠ setup_fprtm_database.sql y los create_*.sql posteriores definen algunas
--   tablas DOS VECES con formas distintas. Aquí se toma la versión de los
--   ficheros create_*.sql por ser los más recientes. Verificar contra el
--   volcado de producción (ver docs/SCHEMA_MANIFEST.md).
-- ============================================================================


-- ────────── create_membership_requests.sql ──────────
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
DROP POLICY IF EXISTS "Public can submit membership requests" ON membership_requests;
CREATE POLICY "Public can submit membership requests"
  ON membership_requests FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Only authenticated users (admin) can read requests
DROP POLICY IF EXISTS "Admin can view membership requests" ON membership_requests;
CREATE POLICY "Admin can view membership requests"
  ON membership_requests FOR SELECT
  TO authenticated
  USING (true);

-- Only authenticated users can update status (approve/reject)
DROP POLICY IF EXISTS "Admin can process membership requests" ON membership_requests;
CREATE POLICY "Admin can process membership requests"
  ON membership_requests FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- ────────── create_photo_requests.sql ──────────
-- ============================================================
-- FPTM — Tabla photo_requests
-- Ejecutar en Supabase → SQL Editor antes de usar fotos
-- ============================================================

CREATE TABLE IF NOT EXISTS photo_requests (
  id         BIGSERIAL    PRIMARY KEY,
  member_id  INT          NOT NULL,
  photo_url  TEXT         NOT NULL,
  status     TEXT         NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_photo_requests_member ON photo_requests (member_id);
CREATE INDEX IF NOT EXISTS idx_photo_requests_status ON photo_requests (status);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE photo_requests ENABLE ROW LEVEL SECURITY;

-- Lectura pública (admin necesita ver pending, app necesita approved)
DROP POLICY IF EXISTS "photo_public_read" ON photo_requests;
CREATE POLICY "photo_public_read"
  ON photo_requests FOR SELECT
  USING (true);

-- Cualquiera puede enviar una solicitud pendiente
DROP POLICY IF EXISTS "photo_anon_insert" ON photo_requests;
CREATE POLICY "photo_anon_insert"
  ON photo_requests FOR INSERT
  WITH CHECK (status = 'pending');

-- Solo el admin puede aprobar / rechazar
DROP POLICY IF EXISTS "photo_admin_update" ON photo_requests;
CREATE POLICY "photo_admin_update"
  ON photo_requests FOR UPDATE
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

-- ── Storage bucket ───────────────────────────────────────────
-- Paso manual en Supabase Dashboard → Storage:
--   1. Crear bucket llamado: player-photos
--   2. Marcar como Public bucket
--   3. En Policies del bucket, crear política:
--        Operation: INSERT
--        Role:      anon
--        Definition: true
-- ─────────────────────────────────────────────────────────────

-- ────────── add_is_minor_to_photo_requests.sql ──────────
-- Migration: Add is_minor field to photo_requests table
-- Purpose: Track whether a photo is of a minor (under 18) to enforce
--          parental/guardian consent disclosure requirements.
--
-- Run this in the Supabase SQL Editor.

ALTER TABLE photo_requests
  ADD COLUMN IF NOT EXISTS is_minor BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN photo_requests.is_minor IS
  'TRUE si el jugador es menor de 18 años. Indica que se requirió y confirmó autorización del tutor legal antes de subir la foto.';

-- ────────── club_change_requests.sql ──────────
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
DROP POLICY IF EXISTS "club_req_insert_public" ON public.club_change_requests;
CREATE POLICY "club_req_insert_public"
  ON public.club_change_requests
  FOR INSERT
  TO public
  WITH CHECK (true);

-- Public can read their own pending requests (optional – needed for duplicate-check)
DROP POLICY IF EXISTS "club_req_select_public" ON public.club_change_requests;
CREATE POLICY "club_req_select_public"
  ON public.club_change_requests
  FOR SELECT
  TO public
  USING (true);

-- Only authenticated admin can UPDATE (approve / reject)
DROP POLICY IF EXISTS "club_req_update_admin" ON public.club_change_requests;
CREATE POLICY "club_req_update_admin"
  ON public.club_change_requests
  FOR UPDATE
  TO authenticated
  USING (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz')
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

-- ────────── create_player_reg_tokens.sql ──────────
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
DROP POLICY IF EXISTS "admin_all_reg_tokens" ON public.player_reg_tokens;
CREATE POLICY "admin_all_reg_tokens"
  ON public.player_reg_tokens FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- Public: can read to validate a token
DROP POLICY IF EXISTS "anon_read_reg_tokens" ON public.player_reg_tokens;
CREATE POLICY "anon_read_reg_tokens"
  ON public.player_reg_tokens FOR SELECT TO anon
  USING (true);

-- Public: can mark an unused token as used (when submitting the form)
DROP POLICY IF EXISTS "anon_use_reg_token" ON public.player_reg_tokens;
CREATE POLICY "anon_use_reg_token"
  ON public.player_reg_tokens FOR UPDATE TO anon
  USING (used = false)
  WITH CHECK (used = true);

-- ────────── create_player_reg_submissions.sql ──────────
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
DROP POLICY IF EXISTS "anon_insert_reg_submissions" ON public.player_reg_submissions;
CREATE POLICY "anon_insert_reg_submissions"
  ON public.player_reg_submissions FOR INSERT TO anon
  WITH CHECK (true);

-- Admin: full access
DROP POLICY IF EXISTS "admin_all_reg_submissions" ON public.player_reg_submissions;
CREATE POLICY "admin_all_reg_submissions"
  ON public.player_reg_submissions FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ────────── create_resultados_draft.sql ──────────
-- Staging table for tournament results before publishing to Base de Datos.
-- Admin uploads CSV → results saved here → admin reviews → publishes.
-- Run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.resultados_draft (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  torneo_nombre     TEXT        NOT NULL,
  torneo_categoria  TEXT,
  torneo_fecha      DATE        NOT NULL,
  partidos          JSONB       NOT NULL,
  snapshot_map      JSONB       NOT NULL,
  col_name          TEXT,       -- e.g. "rating_morovis_open_2026"
  status            TEXT        DEFAULT 'pending',
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  published_at      TIMESTAMPTZ
);

-- Allow admins (authenticated) to do everything
ALTER TABLE public.resultados_draft ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can manage drafts" ON public.resultados_draft;
CREATE POLICY "Authenticated can manage drafts"
  ON public.resultados_draft
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);


-- ────────── resultados_draft: categoría del lote pendiente ──────────
-- desde add_categoria_partidos.sql (movido desde 020_core_alterations: depende de la tabla
-- creada justo arriba).
ALTER TABLE public.resultados_draft
  ADD COLUMN IF NOT EXISTS torneo_categoria TEXT;
