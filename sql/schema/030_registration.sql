-- ============================================================================
-- 030 · Inscripciones
--
-- Depende de: 010 ("Base de Datos" — insc_registro.member_id apunta ahí
-- por convención, sin FK declarada).
--
-- Origen (curado): create_insc_registro.sql + los parches add_*.sql que le
-- añaden columnas. Se omiten los SELECT de verificación de los originales.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.insc_registro (
  id         BIGSERIAL PRIMARY KEY,
  torneo     TEXT        NOT NULL DEFAULT 'Morovis Open 2026',
  member_id  INTEGER     NOT NULL,
  nombre     TEXT        NOT NULL,
  fptm_id    TEXT        NOT NULL,
  categorias JSONB       NOT NULL DEFAULT '[]',
  base       NUMERIC(6,2) NOT NULL DEFAULT 0,
  total      NUMERIC(6,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (torneo, member_id)
);

ALTER TABLE public.insc_registro ENABLE ROW LEVEL SECURITY;

-- Cualquier visitante puede registrarse (INSERT/UPDATE de su propia entrada)
DROP POLICY IF EXISTS "public_insert_insc_registro" ON public.insc_registro;
CREATE POLICY "public_insert_insc_registro"
  ON public.insc_registro FOR INSERT TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "public_update_insc_registro" ON public.insc_registro;
CREATE POLICY "public_update_insc_registro"
  ON public.insc_registro FOR UPDATE TO anon, authenticated
  USING (true) WITH CHECK (true);

-- Solo el admin puede ver el listado
DROP POLICY IF EXISTS "admin_select_insc_registro" ON public.insc_registro;
CREATE POLICY "admin_select_insc_registro"
  ON public.insc_registro FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "admin_delete_insc_registro" ON public.insc_registro;
CREATE POLICY "admin_delete_insc_registro"
  ON public.insc_registro FOR DELETE TO authenticated
  USING (true);


-- ── Parches de columnas ─────────────────────────────────────────────────────
-- Enunciados completos desde los add_*.sql. Se omite el UPDATE de relleno de
-- add_monto_pagado.sql (migraba filas existentes; en una base vacía no aplica)
-- y sus SELECT de verificación.

-- desde add_club_insc_registro.sql
ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS club TEXT;

-- desde add_dob_sex_insc_registro.sql
ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS dob  TEXT,
  ADD COLUMN IF NOT EXISTS sex  TEXT;

-- desde add_pagado_insc_registro.sql
ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS pagado BOOLEAN DEFAULT FALSE;

-- desde add_referencia_insc_registro.sql
ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS referencia TEXT;

-- desde add_monto_pagado.sql
ALTER TABLE public.insc_registro
  ADD COLUMN IF NOT EXISTS monto_pagado NUMERIC DEFAULT 0;


-- ── Lectura pública de inscripciones ────────────────────────────────────────
-- desde fix_insc_registro_public_select.sql
DROP POLICY IF EXISTS "public_select_insc_registro" ON public.insc_registro;
CREATE POLICY "public_select_insc_registro"
  ON public.insc_registro FOR SELECT TO anon
  USING (true);
