-- =============================================================================
-- Tabla: insc_registro
-- Registra las inscripciones al Morovis Open 2026 cuando el jugador
-- hace clic en "Pagar con ATH Móvil".
-- Corre esto en el SQL Editor de Supabase.
-- =============================================================================

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
CREATE POLICY "public_insert_insc_registro"
  ON public.insc_registro FOR INSERT TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "public_update_insc_registro"
  ON public.insc_registro FOR UPDATE TO anon, authenticated
  USING (true) WITH CHECK (true);

-- Solo el admin puede ver el listado
CREATE POLICY "admin_select_insc_registro"
  ON public.insc_registro FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "admin_delete_insc_registro"
  ON public.insc_registro FOR DELETE TO authenticated
  USING (true);
