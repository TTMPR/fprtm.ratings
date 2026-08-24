-- ============================================================
--  FPTM — Permitir editar y borrar torneos desde la app
--  Ejecutar en: Supabase → SQL Editor
--
--  supabase_security_fixes.sql creó políticas SOLO para INSERT en
--  torneos y partidos. Con RLS activo y sin política de UPDATE o
--  DELETE, esas operaciones afectan CERO filas y PostgREST responde
--  204 (éxito) igual — por eso borrar un torneo desde el Admin
--  parecía funcionar y el torneo seguía ahí.
--
--  Se restringe al mismo correo de administrador que ya usan las
--  políticas de INSERT. Si hay más de un admin, añade su correo a
--  la lista de la constante de abajo.
-- ============================================================

-- ── torneos ────────────────────────────────────────────────
DROP POLICY IF EXISTS "update_torneos" ON public.torneos;
CREATE POLICY "update_torneos" ON public.torneos
  FOR UPDATE TO authenticated
  USING      (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'))
  WITH CHECK (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

DROP POLICY IF EXISTS "delete_torneos" ON public.torneos;
CREATE POLICY "delete_torneos" ON public.torneos
  FOR DELETE TO authenticated
  USING (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

-- ── partidos ───────────────────────────────────────────────
DROP POLICY IF EXISTS "update_partidos" ON public.partidos;
CREATE POLICY "update_partidos" ON public.partidos
  FOR UPDATE TO authenticated
  USING      (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'))
  WITH CHECK (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

DROP POLICY IF EXISTS "delete_partidos" ON public.partidos;
CREATE POLICY "delete_partidos" ON public.partidos
  FOR DELETE TO authenticated
  USING (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

-- ── resultados_evento ──────────────────────────────────────
DROP POLICY IF EXISTS "update_resultados_evento" ON public.resultados_evento;
CREATE POLICY "update_resultados_evento" ON public.resultados_evento
  FOR UPDATE TO authenticated
  USING      (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'))
  WITH CHECK (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

DROP POLICY IF EXISTS "delete_resultados_evento" ON public.resultados_evento;
CREATE POLICY "delete_resultados_evento" ON public.resultados_evento
  FOR DELETE TO authenticated
  USING (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

-- ── Verificar ──────────────────────────────────────────────
-- Debe listar update_* y delete_* para las tres tablas.
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('torneos', 'partidos', 'resultados_evento')
ORDER BY tablename, cmd, policyname;

-- Si tu cuenta de admin NO es joel@ttmpr.xyz, este query te dice
-- con qué correo estás entrando (córrelo desde la app, no aquí):
--   SELECT auth.jwt() ->> 'email';
