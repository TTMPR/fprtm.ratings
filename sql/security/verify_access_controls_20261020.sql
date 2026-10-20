-- Read-only security regression checks for official FPTM Supabase.
-- Run after schema migrations, before reopening registrations or publishing.
-- This script makes no data changes.
BEGIN;
DO $security$
BEGIN
 IF has_table_privilege('anon','public."Base de Datos"','SELECT') THEN
  RAISE EXCEPTION 'Public raw athlete registry exposed';
 END IF;
 IF has_table_privilege('anon','public.membership_requests','SELECT') THEN
  RAISE EXCEPTION 'Public membership requests exposed';
 END IF;
 IF has_table_privilege('anon','public.player_reg_tokens','SELECT')
 OR has_table_privilege('anon','public.player_reg_tokens','UPDATE')
 OR has_table_privilege('anon','public.player_reg_submissions','INSERT') THEN
  RAISE EXCEPTION 'Public one-time token registry exposed';
 END IF;
 IF has_column_privilege('anon','public.insc_registro','dob','SELECT')
 OR has_column_privilege('anon','public.insc_registro','referencia','SELECT') THEN
  RAISE EXCEPTION 'Public tournament PII exposed';
 END IF;
 IF NOT has_table_privilege('anon','public.api_jugadores','SELECT') THEN
  RAISE EXCEPTION 'Sanitized public directory unavailable';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_class c
   WHERE c.oid IN ('public.api_jugadores'::regclass,
                   'public.insc_busca_companero_publico'::regclass)
   AND NOT ('security_invoker=true'=ANY(COALESCE(c.reloptions,ARRAY[]::text[])))) THEN
  RAISE EXCEPTION 'Public views bypass security invoker';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prosecdef
   AND (has_function_privilege('anon',p.oid,'EXECUTE')
     OR has_function_privilege('authenticated',p.oid,'EXECUTE'))) THEN
  RAISE EXCEPTION 'Public callable SECURITY DEFINER function';
 END IF;
 IF (SELECT b.public FROM storage.buckets b WHERE b.id='player-photos') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Pending player photos are publicly accessible';
 END IF;
END $security$;
SELECT 'PASS' AS security_baseline;
ROLLBACK;
