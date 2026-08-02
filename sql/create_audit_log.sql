-- =============================================================================
-- FPTM · Fase 3.1/3.2 — Audit log (caja negra de cambios)
--
-- ⚠️  REVISAR ANTES DE APLICAR. Correr en el Supabase SQL Editor.
--     Es aditivo: no modifica datos ni políticas existentes.
--
-- Qué hace:
--   1. Crea la tabla audit_log (quién, qué, cuándo, valor anterior y nuevo).
--   2. RLS: solo el admin (joel@ttmpr.xyz, autenticado) puede LEERLA vía API.
--      Nadie puede insertarla/editarla/borrarla vía API — solo escribe el
--      trigger (SECURITY DEFINER). Es append-only desde la aplicación.
--   3. Trigger genérico fn_audit() aplicado a las tablas críticas.
--
-- Nota sobre la columna "actor": registra el email del JWT si la petición
-- llegó autenticada. Las escrituras que la app hace con la anon key (la
-- mayoría de sbPatch/sbPost actuales) quedan como 'anon'. Como el único
-- admin es Joel, en la práctica 'anon' en tablas de admin = Joel; si algún
-- día hay más admins, conviene migrar la app a enviar el JWT de sesión.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. Tabla
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  actor       text,                -- email del JWT o 'anon'
  action      text NOT NULL,       -- 'INSERT' | 'UPDATE' | 'DELETE'
  table_name  text NOT NULL,
  record_id   text,                -- PK del registro afectado (como texto)
  old_data    jsonb,               -- fila antes del cambio (UPDATE/DELETE)
  new_data    jsonb                -- fila después del cambio (INSERT/UPDATE)
);

-- Índices para los filtros de la vista de Historial (tabla / fecha / registro)
CREATE INDEX IF NOT EXISTS audit_log_occurred_at_idx ON public.audit_log (occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_table_name_idx  ON public.audit_log (table_name);
CREATE INDEX IF NOT EXISTS audit_log_record_id_idx   ON public.audit_log (record_id);


-- ---------------------------------------------------------------------------
-- 2. RLS: lectura solo para el admin; sin escritura vía API
-- ---------------------------------------------------------------------------
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_log_admin_read" ON public.audit_log;
CREATE POLICY "audit_log_admin_read" ON public.audit_log
  FOR SELECT
  TO authenticated
  USING (auth.jwt() ->> 'email' = 'joel@ttmpr.xyz');

-- Deliberadamente NO se crean políticas de INSERT/UPDATE/DELETE:
-- con RLS activo y sin política, la API rechaza cualquier escritura.
-- El trigger escribe igual porque fn_audit es SECURITY DEFINER.


-- ---------------------------------------------------------------------------
-- 3. Función de trigger genérica
--    Acepta el nombre de la columna PK como argumento (default 'id'),
--    necesario para "Base de Datos" cuya PK es "Member ID".
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_audit() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  pk  text;
  rid text;
BEGIN
  pk  := COALESCE(TG_ARGV[0], 'id');
  rid := COALESCE(to_jsonb(NEW) ->> pk, to_jsonb(OLD) ->> pk);

  INSERT INTO public.audit_log (actor, action, table_name, record_id, old_data, new_data)
  VALUES (
    COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', 'anon'),
    TG_OP,
    TG_TABLE_NAME,
    rid,
    CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;


-- ---------------------------------------------------------------------------
-- 4. Triggers en las tablas críticas
--    (ratings/jugadores, partidos, torneos, resultados, membresías,
--     inscripciones). DROP IF EXISTS para que el script sea re-ejecutable.
-- ---------------------------------------------------------------------------

-- Ratings oficiales (PK: "Member ID")
DROP TRIGGER IF EXISTS trg_audit_base_de_datos ON public."Base de Datos";
CREATE TRIGGER trg_audit_base_de_datos
  AFTER INSERT OR UPDATE OR DELETE ON public."Base de Datos"
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit('Member ID');

-- Jugadores (tabla espejo usada por la app al revertir ratings)
DROP TRIGGER IF EXISTS trg_audit_jugadores ON public.jugadores;
CREATE TRIGGER trg_audit_jugadores
  AFTER INSERT OR UPDATE OR DELETE ON public.jugadores
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

DROP TRIGGER IF EXISTS trg_audit_partidos ON public.partidos;
CREATE TRIGGER trg_audit_partidos
  AFTER INSERT OR UPDATE OR DELETE ON public.partidos
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

DROP TRIGGER IF EXISTS trg_audit_torneos ON public.torneos;
CREATE TRIGGER trg_audit_torneos
  AFTER INSERT OR UPDATE OR DELETE ON public.torneos
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

DROP TRIGGER IF EXISTS trg_audit_resultados_evento ON public.resultados_evento;
CREATE TRIGGER trg_audit_resultados_evento
  AFTER INSERT OR UPDATE OR DELETE ON public.resultados_evento
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

DROP TRIGGER IF EXISTS trg_audit_membership_requests ON public.membership_requests;
CREATE TRIGGER trg_audit_membership_requests
  AFTER INSERT OR UPDATE OR DELETE ON public.membership_requests
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

DROP TRIGGER IF EXISTS trg_audit_insc_registro ON public.insc_registro;
CREATE TRIGGER trg_audit_insc_registro
  AFTER INSERT OR UPDATE OR DELETE ON public.insc_registro
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();


-- ---------------------------------------------------------------------------
-- 5. (Opcional, comentado) Retención: borrar entradas de más de 1 año.
--    El log crece ~1 fila por cada cambio. Con el volumen actual de la
--    federación no es problema en años; si algún día lo es, descomentar y
--    programar con pg_cron:
--
-- SELECT cron.schedule('purge-audit-log', '0 4 1 * *',
--   $$DELETE FROM public.audit_log WHERE occurred_at < now() - interval '1 year'$$);
-- ---------------------------------------------------------------------------


-- Verificación rápida tras aplicar (debe devolver una fila por trigger):
-- SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE tgname LIKE 'trg_audit%';
