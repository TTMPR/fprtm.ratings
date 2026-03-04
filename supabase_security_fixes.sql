-- =============================================================================
-- FPRTM Security Fixes
-- Run these statements in the Supabase SQL Editor (or via psql).
-- Addresses all ERRORs and WARNs from the database security linter.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Enable RLS on "Base de Datos"
--    Fixes: policy_exists_rls_disabled  (ERROR)
--           rls_disabled_in_public      (ERROR)
-- ---------------------------------------------------------------------------
ALTER TABLE "public"."Base de Datos" ENABLE ROW LEVEL SECURITY;

-- The existing allow_public_read policy is kept as-is (SELECT USING (true)
-- is intentional for public read access and is NOT flagged by the linter).


-- ---------------------------------------------------------------------------
-- 2. Fix SECURITY DEFINER view: miembros_alertas
--    Fixes: security_definer_view  (ERROR)
--
--    Postgres 15+: flip the view to SECURITY INVOKER so it runs under the
--    querying user's permissions instead of the view owner's.
-- ---------------------------------------------------------------------------
ALTER VIEW "public"."miembros_alertas" SET (security_invoker = on);


-- ---------------------------------------------------------------------------
-- 3. Pin search_path on update_updated_at
--    Fixes: function_search_path_mutable  (WARN)
--
--    A mutable search_path lets an attacker shadow pg_catalog objects.
--    Setting it to '' forces fully-qualified names and eliminates the risk.
-- ---------------------------------------------------------------------------
ALTER FUNCTION "public"."update_updated_at"()
  SET search_path = '';


-- ---------------------------------------------------------------------------
-- 4. Restrict INSERT policies to the single admin account
--    Fixes: rls_policy_always_true on partidos  (WARN)
--           rls_policy_always_true on torneos   (WARN)
--
--    WITH CHECK (true) for INSERT lets any authenticated user insert any row.
--    Replaced with a check that the JWT email matches the admin account.
--    Change 'admin@fprtm.com' if the admin email is different.
-- ---------------------------------------------------------------------------

-- partidos
DROP POLICY IF EXISTS "insert_partidos" ON "public"."partidos";
CREATE POLICY "insert_partidos" ON "public"."partidos"
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'admin@fprtm.com');

-- torneos
DROP POLICY IF EXISTS "insert_torneos" ON "public"."torneos";
CREATE POLICY "insert_torneos" ON "public"."torneos"
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'admin@fprtm.com');


-- ---------------------------------------------------------------------------
-- 5. Leaked Password Protection  (WARN)
--    This cannot be fixed via SQL — enable it in the Supabase Dashboard:
--    Authentication → Providers → Email → "Enable Leaked Password Protection"
--    (checks passwords against HaveIBeenPwned.org before allowing sign-up /
--    password change)
-- ---------------------------------------------------------------------------
