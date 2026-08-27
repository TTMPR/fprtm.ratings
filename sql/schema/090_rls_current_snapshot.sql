-- ============================================================================
-- 090 · RLS sobre las tablas núcleo — FOTO DEL ESTADO ACTUAL
--
-- Depende de: 010 (las tablas núcleo deben existir).
--
-- ⚠️  ESTE FICHERO REPRODUCE PRODUCCIÓN, INCLUIDAS SUS DEBILIDADES.
--
-- Es deliberado. Staging tiene que empezar pareciéndose a producción; si
-- aquí se "arregla" la seguridad por el camino, staging deja de reproducir
-- el sistema real y los tests dejan de significar nada. El endurecimiento
-- ocurre DESPUÉS, en la Fase 1.2/1.3, y se prueba en staging antes de tocar
-- producción.
--
-- Hallazgos conocidos que este fichero reproduce a propósito
-- (ver SECURITY_FINDINGS.md):
--   F-02  "Base de Datos" con SELECT USING (true): la llave publicable lee
--         Email, Home Address y Date of Birth
--   F-05  identidad de administrador escrita a mano (joel@ttmpr.xyz)
--
-- NO CORRIJAS NADA AQUÍ sin aprobación explícita.
--
-- Origen (curado):
--   supabase_security_fixes.sql
--   fix_base_datos_rls.sql
--   fix_rls_torneos_borrar.sql
--   setup_fprtm_database.sql (sección de seguridad)
-- ============================================================================


-- ── Constante de administrador ──────────────────────────────────────────────
-- El correo va literal en cada política, igual que en producción. Se deja
-- así a propósito: parametrizarlo aquí sería ya el arreglo de F-05.
-- Si el correo de administración cambia, hay que editar todas las políticas
-- de este fichero — ése es exactamente el problema que F-05 describe.


-- ============================================================================
-- "Base de Datos"
-- ============================================================================

ALTER TABLE public."Base de Datos" ENABLE ROW LEVEL SECURITY;

-- ⚠️ F-02 · La política de SELECT `allow_public_read` (USING (true)) NO está
--    en ningún fichero del repositorio: existe sólo en producción. No se
--    reproduce aquí porque su definición exacta (nombre, roles) no se ha
--    verificado. RECUPERARLA del volcado de producción y añadirla aquí tal
--    cual — sin corregirla — antes de considerar completo este fichero.
--    Ver docs/STAGING_RUNBOOK.md.

DROP POLICY IF EXISTS "admin_insert_base_datos" ON public."Base de Datos";
CREATE POLICY "admin_insert_base_datos"
  ON public."Base de Datos"
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

DROP POLICY IF EXISTS "admin_update_base_datos" ON public."Base de Datos";
CREATE POLICY "admin_update_base_datos"
  ON public."Base de Datos"
  FOR UPDATE
  TO authenticated
  USING      (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz')
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');


-- ============================================================================
-- torneos
-- ============================================================================

DROP POLICY IF EXISTS "insert_torneos" ON public.torneos;
CREATE POLICY "insert_torneos" ON public.torneos
  FOR INSERT TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

DROP POLICY IF EXISTS "update_torneos" ON public.torneos;
CREATE POLICY "update_torneos" ON public.torneos
  FOR UPDATE TO authenticated
  USING      (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'))
  WITH CHECK (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

DROP POLICY IF EXISTS "delete_torneos" ON public.torneos;
CREATE POLICY "delete_torneos" ON public.torneos
  FOR DELETE TO authenticated
  USING (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));


-- ============================================================================
-- partidos
-- ============================================================================

DROP POLICY IF EXISTS "insert_partidos" ON public.partidos;
CREATE POLICY "insert_partidos" ON public.partidos
  FOR INSERT TO authenticated
  WITH CHECK (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

DROP POLICY IF EXISTS "update_partidos" ON public.partidos;
CREATE POLICY "update_partidos" ON public.partidos
  FOR UPDATE TO authenticated
  USING      (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'))
  WITH CHECK (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

DROP POLICY IF EXISTS "delete_partidos" ON public.partidos;
CREATE POLICY "delete_partidos" ON public.partidos
  FOR DELETE TO authenticated
  USING (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));


-- ============================================================================
-- resultados_evento
-- ============================================================================

DROP POLICY IF EXISTS "update_resultados_evento" ON public.resultados_evento;
CREATE POLICY "update_resultados_evento" ON public.resultados_evento
  FOR UPDATE TO authenticated
  USING      (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'))
  WITH CHECK (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));

DROP POLICY IF EXISTS "delete_resultados_evento" ON public.resultados_evento;
CREATE POLICY "delete_resultados_evento" ON public.resultados_evento
  FOR DELETE TO authenticated
  USING (auth.jwt() ->> 'email' IN ('joel@ttmpr.xyz'));


-- ============================================================================
-- HUECOS CONOCIDOS EN ESTE FICHERO
-- ============================================================================
--
-- Las siguientes políticas y objetos se sabe que existen en producción pero
-- NO están definidos en ningún fichero del repositorio. No se han inventado.
-- Hay que recuperarlos del volcado antes de dar staging por equivalente:
--
--   · La política de SELECT sobre "Base de Datos" (allow_public_read)
--   · Las políticas de SELECT sobre torneos, partidos y resultados_evento
--     (la app lee esas tablas sin sesión, así que existen)
--   · Las políticas de INSERT sobre resultados_evento (subirApplyRatings
--     escribe ahí)
--   · La vista public.miembros_alertas
--     (supabase_security_fixes.sql la ALTERa, nadie la CREA)
--   · La función public.update_updated_at()
--     (mismo caso: se le fija search_path, nunca se define)
