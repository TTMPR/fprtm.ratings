-- ============================================================================
--  FPTM — Tablón "Busco Compañero"
--  Ejecutar en: Supabase → SQL Editor  (seguro de re-ejecutar)
--
--  Para torneos por equipos o de dobles: quien no tiene pareja publica que
--  busca, y los demás lo ven. Se guarda por torneo, así que sirve para la
--  Copa Olímpica ahora y para cualquier evento futuro sin tocar el esquema.
--
--  Decisión de la federación: el contacto es PÚBLICO y opcional. Quien
--  publica escoge si pone WhatsApp, email o nada. Queda visible para
--  cualquiera que abra la página — así es como funciona un tablón.
--
--  La excepción son los menores. Un menor de 18 no publica contacto: su
--  anuncio sale, pero quien quiera contactarlo pasa por la FPTM. Y esa
--  decisión NO la toma el navegador: se calcula aquí, contra la fecha de
--  nacimiento de "Base de Datos". Si el formulario mintiera o fallara, el
--  teléfono del menor seguiría sin publicarse.
--
--  Requiere sql/create_insc_equipos.sql: la vista pública esconde a quien ya
--  aparece en un equipo inscrito, y eso se consulta contra insc_equipos.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. HELPER: fecha de nacimiento → DATE
--    "Date of Birth" es TEXT con tres formatos históricos mezclados. Esta
--    función replica lo justo de _parseDOBStr() del index.html.
--
--    Sí, sql/create_api_publica.sql tiene una versión más completa
--    (fprtm_parse_fecha). No se reutiliza a propósito: ese script es para la
--    página oficial y puede no haberse corrido en esta base. Que el tablón
--    dependa de él sería que un menor publique su teléfono porque faltaba
--    correr un archivo que no tiene nada que ver.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.insc_dob_a_fecha(raw TEXT)
RETURNS DATE
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE
  t TEXT; m TEXT[]; yy INT;
  meses CONSTANT TEXT[] := ARRAY['jan','feb','mar','apr','may','jun',
                                 'jul','aug','sep','oct','nov','dec'];
BEGIN
  IF raw IS NULL THEN RETURN NULL; END IF;
  t := btrim(raw);
  IF t = '' THEN RETURN NULL; END IF;

  -- ISO: 2001-11-25
  m := regexp_match(t, '^(\d{4})-(\d{1,2})-(\d{1,2})$');
  IF m IS NOT NULL THEN
    BEGIN RETURN make_date(m[1]::INT, m[2]::INT, m[3]::INT);
    EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  END IF;

  -- D-Mon-YY(YY): 25-Nov-01
  m := regexp_match(lower(t), '^(\d{1,2})-([a-z]{3})-(\d{2,4})$');
  IF m IS NOT NULL THEN
    yy := m[3]::INT;
    IF length(m[3]) = 2 THEN yy := CASE WHEN yy < 30 THEN 2000 + yy ELSE 1900 + yy END; END IF;
    BEGIN RETURN make_date(yy, array_position(meses, m[2]), m[1]::INT);
    EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  END IF;

  -- M/D/YY(YY): 11/25/2001
  m := regexp_match(t, '^(\d{1,2})/(\d{1,2})/(\d{2,4})$');
  IF m IS NOT NULL THEN
    yy := m[3]::INT;
    IF length(m[3]) = 2 THEN yy := CASE WHEN yy < 30 THEN 2000 + yy ELSE 1900 + yy END; END IF;
    BEGIN RETURN make_date(yy, m[1]::INT, m[2]::INT);
    EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  END IF;

  RETURN NULL;
END;
$$;

-- ¿Es menor de 18 hoy? NULL cuando no hay fecha utilizable en la base.
CREATE OR REPLACE FUNCTION public.insc_es_menor(p_member_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_dob DATE;
BEGIN
  IF p_member_id IS NULL THEN RETURN NULL; END IF;
  SELECT public.insc_dob_a_fecha(b."Date of Birth") INTO v_dob
    FROM public."Base de Datos" b WHERE b."Member ID" = p_member_id;
  IF v_dob IS NULL THEN RETURN NULL; END IF;
  RETURN v_dob > (CURRENT_DATE - INTERVAL '18 years');
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;   -- columna o tabla distinta de lo esperado: decide quien llama
END;
$$;


-- ---------------------------------------------------------------------------
-- 2. TABLA
--    estado: activo | emparejado | retirado | oculto  (oculto = lo bajó el admin)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.insc_busca_companero (
  id             BIGSERIAL PRIMARY KEY,
  torneo         TEXT NOT NULL,
  member_id      INTEGER,
  nombre         TEXT NOT NULL,
  nombre_norm    TEXT NOT NULL,
  rating         INTEGER,
  club           TEXT,
  nota           TEXT,
  contacto_tipo  TEXT NOT NULL DEFAULT 'ninguno',
  contacto_valor TEXT,
  es_menor       BOOLEAN NOT NULL DEFAULT FALSE,
  estado         TEXT NOT NULL DEFAULT 'activo',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT insc_busca_estado_chk   CHECK (estado IN ('activo','emparejado','retirado','oculto')),
  CONSTRAINT insc_busca_contacto_chk CHECK (contacto_tipo IN ('whatsapp','email','ninguno'))
);

-- Un anuncio activo por persona y torneo. Quien se retira puede volver a publicar.
CREATE UNIQUE INDEX IF NOT EXISTS insc_busca_uniq_member
  ON public.insc_busca_companero (torneo, member_id)
  WHERE member_id IS NOT NULL AND estado = 'activo';
CREATE UNIQUE INDEX IF NOT EXISTS insc_busca_uniq_invitado
  ON public.insc_busca_companero (torneo, nombre_norm)
  WHERE member_id IS NULL AND estado = 'activo';
CREATE INDEX IF NOT EXISTS insc_busca_torneo_idx
  ON public.insc_busca_companero (torneo, estado);

CREATE OR REPLACE FUNCTION public.insc_busca_touch()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN NEW.updated_at := NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS insc_busca_touch_trg ON public.insc_busca_companero;
CREATE TRIGGER insc_busca_touch_trg
  BEFORE UPDATE ON public.insc_busca_companero
  FOR EACH ROW EXECUTE FUNCTION public.insc_busca_touch();


-- ---------------------------------------------------------------------------
-- 3. VISTA PÚBLICA
--    Dos cosas pasan aquí y no en el navegador:
--      · quien ya está en un equipo inscrito desaparece del tablón — nadie
--        tiene que acordarse de retirar su anuncio;
--      · el contacto de un menor no sale, pase lo que pase.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.insc_busca_companero_publico
WITH (security_invoker = off) AS
SELECT
  b.id, b.torneo, b.member_id, b.nombre, b.rating, b.club, b.nota,
  b.es_menor,
  CASE WHEN b.es_menor THEN 'ninguno' ELSE b.contacto_tipo  END AS contacto_tipo,
  CASE WHEN b.es_menor THEN NULL      ELSE b.contacto_valor END AS contacto_valor,
  b.created_at
FROM public.insc_busca_companero b
WHERE b.estado = 'activo'
  AND NOT EXISTS (
    SELECT 1 FROM public.insc_equipos e
     WHERE e.torneo = b.torneo
       AND e.estado IN ('reservado','confirmado','lista_espera','pendiente_division')
       AND ( (b.member_id IS NOT NULL AND b.member_id IN (e.cap_member_id, e.comp_member_id))
          OR (b.member_id IS NULL AND b.nombre_norm IN (public.insc_nombre_norm(e.cap_nombre),
                                                        public.insc_nombre_norm(e.comp_nombre))) )
  );


-- ---------------------------------------------------------------------------
-- 4. PUBLICAR ANUNCIO
--
--  p_adulto_declarado solo se usa cuando la base no tiene fecha de nacimiento
--  utilizable. Con fecha, manda la fecha. Sin fecha y sin declaración, el
--  contacto no se publica: preferimos un anuncio sin teléfono a publicar el
--  de un menor por no saberlo.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publicar_busca_companero(
  p_torneo           TEXT,
  p_member_id        INTEGER,
  p_nombre           TEXT,
  p_rating           INTEGER  DEFAULT NULL,
  p_club             TEXT     DEFAULT NULL,
  p_nota             TEXT     DEFAULT NULL,
  p_contacto_tipo    TEXT     DEFAULT 'ninguno',
  p_contacto_valor   TEXT     DEFAULT NULL,
  p_adulto_declarado BOOLEAN  DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_norm    TEXT := public.insc_nombre_norm(p_nombre);
  v_abierto TEXT;
  v_cierre  TEXT;
  v_menor   BOOLEAN;
  v_tipo    TEXT := lower(COALESCE(btrim(p_contacto_tipo), 'ninguno'));
  v_valor   TEXT := NULLIF(btrim(COALESCE(p_contacto_valor, '')), '');
  v_equipo  RECORD;
  v_id      BIGINT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_busca:' || p_torneo));

  IF v_norm = '' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'incompleto',
      'error', 'Hace falta tu nombre.');
  END IF;

  SELECT value INTO v_abierto FROM public.app_settings WHERE key = 'inscripciones_open';
  IF COALESCE(v_abierto, 'false') <> 'true' THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'cerradas',
      'error', 'Las inscripciones no están abiertas en este momento.');
  END IF;

  SELECT value INTO v_cierre FROM public.app_settings WHERE key = 'insc_equipos_cierre';
  IF v_cierre IS NOT NULL AND btrim(v_cierre) <> '' THEN
    BEGIN
      IF NOW() > v_cierre::TIMESTAMPTZ THEN
        RETURN jsonb_build_object('ok', false, 'codigo', 'fecha_limite',
          'error', 'La fecha límite de inscripción ya pasó.');
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  -- Quien ya tiene equipo no busca compañero
  SELECT cap_nombre, comp_nombre INTO v_equipo
    FROM public.insc_equipos
   WHERE torneo = p_torneo
     AND estado IN ('reservado','confirmado','lista_espera','pendiente_division')
     AND ( (p_member_id IS NOT NULL AND p_member_id IN (cap_member_id, comp_member_id))
        OR (p_member_id IS NULL AND v_norm IN (public.insc_nombre_norm(cap_nombre),
                                               public.insc_nombre_norm(comp_nombre))) )
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', false, 'codigo', 'ya_tiene_equipo',
      'equipo', v_equipo.cap_nombre || ' / ' || v_equipo.comp_nombre,
      'error', 'Ya estás inscrito/a en el equipo ' || v_equipo.cap_nombre || ' / ' || v_equipo.comp_nombre || '.');
  END IF;

  -- Edad: manda la base; la declaración solo cubre el hueco
  v_menor := public.insc_es_menor(p_member_id);
  IF v_menor IS NULL THEN
    v_menor := NOT COALESCE(p_adulto_declarado, FALSE);
  END IF;

  IF v_tipo NOT IN ('whatsapp','email') OR v_valor IS NULL THEN
    v_tipo := 'ninguno'; v_valor := NULL;
  END IF;
  IF v_menor THEN
    v_tipo := 'ninguno'; v_valor := NULL;
  END IF;

  -- Republicar reemplaza el anuncio anterior en vez de duplicarlo
  UPDATE public.insc_busca_companero
     SET estado = 'retirado'
   WHERE torneo = p_torneo AND estado = 'activo'
     AND ( (p_member_id IS NOT NULL AND member_id = p_member_id)
        OR (p_member_id IS NULL AND member_id IS NULL AND nombre_norm = v_norm) );

  INSERT INTO public.insc_busca_companero
    (torneo, member_id, nombre, nombre_norm, rating, club, nota,
     contacto_tipo, contacto_valor, es_menor)
  VALUES
    (p_torneo, p_member_id, btrim(p_nombre), v_norm, p_rating,
     NULLIF(btrim(COALESCE(p_club, '')), ''),
     NULLIF(btrim(COALESCE(p_nota, '')), ''),
     v_tipo, v_valor, v_menor)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id,
    'es_menor', v_menor, 'contacto_publicado', v_tipo <> 'ninguno');
END;
$$;


-- ---------------------------------------------------------------------------
-- 5. RETIRAR ANUNCIO ("ya encontré compañero")
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retirar_busca_companero(p_id BIGINT, p_torneo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n INTEGER;
BEGIN
  UPDATE public.insc_busca_companero
     SET estado = 'emparejado'
   WHERE id = p_id AND torneo = p_torneo AND estado = 'activo';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', v_n > 0);
END;
$$;


-- ---------------------------------------------------------------------------
-- 6. PERMISOS
-- ---------------------------------------------------------------------------
ALTER TABLE public.insc_busca_companero ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_all_insc_busca ON public.insc_busca_companero;
CREATE POLICY admin_all_insc_busca
  ON public.insc_busca_companero FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

REVOKE ALL    ON public.insc_busca_companero FROM anon;
GRANT  ALL    ON public.insc_busca_companero TO   authenticated;
GRANT  SELECT ON public.insc_busca_companero_publico TO anon, authenticated;
GRANT  USAGE, SELECT ON SEQUENCE public.insc_busca_companero_id_seq TO authenticated;

GRANT EXECUTE ON FUNCTION public.publicar_busca_companero(
  TEXT, INTEGER, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.retirar_busca_companero(BIGINT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insc_es_menor(INTEGER)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.insc_dob_a_fecha(TEXT)   TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 7. VERIFICACIÓN
-- ---------------------------------------------------------------------------
SELECT nombre, rating, contacto_tipo, es_menor
  FROM public.insc_busca_companero_publico
 WHERE torneo = 'Copa Olímpica 2026'
 ORDER BY rating DESC NULLS LAST;
