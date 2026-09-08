-- ============================================================================
--  FPTM — Quitar inscripciones duplicadas
--  Correr en: Supabase → SQL Editor
--
--  POR QUÉ HACEN FALTA
--  Con el comportamiento viejo, una reserva sin pagar se expiraba sola a las
--  48 h. Como una fila expirada no cuenta como activa, ese jugador podía
--  volver a inscribirse — y muchos lo hicieron. Al restaurar las expiradas,
--  esas personas quedaron en dos equipos a la vez.
--
--  QUÉ HACE
--  Recorre los equipos activos del más viejo al más nuevo y va "reclamando"
--  jugadores. El primer equipo en que aparece cada jugador se conserva; los
--  posteriores que repitan a alguien ya reclamado se cancelan. Es decir:
--  MANDA LA INSCRIPCIÓN MÁS ANTIGUA, que es lo que pidió la federación.
--
--  EL DINERO NO SE PIERDE
--  Si un equipo que se cancela tenía pagos, el monto y su referencia pasan al
--  equipo que se conserva, y el informe dice exactamente cuánto se movió y de
--  dónde. Nunca se descarta un pago en silencio.
--
--  CÓMO USARLO — dos pasos, y el primero no cambia nada:
--     SELECT * FROM insc_equipos_deduplicar('Copa Olímpica 2026');        -- ensayo
--     SELECT * FROM insc_equipos_deduplicar('Copa Olímpica 2026', true);  -- aplicar
-- ============================================================================

CREATE OR REPLACE FUNCTION public.insc_equipos_deduplicar(
  p_torneo  TEXT,
  p_aplicar BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  accion           TEXT,
  equipo_id        BIGINT,
  equipo           TEXT,
  inscrito         TIMESTAMPTZ,
  estado_actual    TEXT,
  jugador_repetido TEXT,
  conserva_id      BIGINT,
  pago_movido      NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r         RECORD;
  v_dueno   BIGINT;
  v_choque  TEXT;
  v_monto   NUMERIC(8,2);
  v_ref     TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('insc_equipos:' || p_torneo));

  -- Registro de quién ya está reclamado y por qué equipo. Temporal: vive solo
  -- lo que dure esta llamada.
  CREATE TEMP TABLE IF NOT EXISTS _dedup_claim (
    clave     TEXT PRIMARY KEY,   -- 'm:<member_id>' o 'n:<nombre normalizado>'
    equipo_id BIGINT,
    nombre    TEXT
  ) ON COMMIT DROP;
  DELETE FROM _dedup_claim;

  FOR r IN
    SELECT * FROM public.insc_equipos
     WHERE torneo = p_torneo AND public.insc_equipo_activo(estado)
     ORDER BY created_at, id            -- el más antiguo manda
  LOOP
    v_dueno  := NULL;
    v_choque := NULL;

    -- ¿Alguno de sus dos jugadores ya fue reclamado por un equipo anterior?
    SELECT c.equipo_id, c.nombre INTO v_dueno, v_choque
      FROM _dedup_claim c
     WHERE c.clave = ANY (ARRAY[
             CASE WHEN r.cap_member_id  IS NOT NULL THEN 'm:' || r.cap_member_id
                  ELSE 'n:' || public.insc_nombre_norm(r.cap_nombre) END,
             CASE WHEN r.comp_member_id IS NOT NULL THEN 'm:' || r.comp_member_id
                  WHEN r.comp_nombre    IS NOT NULL THEN 'n:' || public.insc_nombre_norm(r.comp_nombre)
                  ELSE NULL END
           ])
     LIMIT 1;

    IF v_dueno IS NULL THEN
      -- Primera vez que vemos a esta gente: el equipo se queda
      INSERT INTO _dedup_claim (clave, equipo_id, nombre)
      SELECT k, r.id, n FROM (VALUES
        (CASE WHEN r.cap_member_id IS NOT NULL THEN 'm:' || r.cap_member_id
              ELSE 'n:' || public.insc_nombre_norm(r.cap_nombre) END, r.cap_nombre),
        (CASE WHEN r.comp_member_id IS NOT NULL THEN 'm:' || r.comp_member_id
              WHEN r.comp_nombre    IS NOT NULL THEN 'n:' || public.insc_nombre_norm(r.comp_nombre)
              ELSE NULL END, r.comp_nombre)
      ) AS v(k, n)
       WHERE k IS NOT NULL
      ON CONFLICT (clave) DO NOTHING;

      accion           := 'conservar';
      equipo_id        := r.id;
      equipo           := r.cap_nombre || ' / ' || COALESCE(r.comp_nombre, '(por definir)');
      inscrito         := r.created_at;
      estado_actual    := r.estado;
      jugador_repetido := NULL;
      conserva_id      := NULL;
      pago_movido      := NULL;
      RETURN NEXT;

    ELSE
      -- Duplicado: este equipo es posterior y repite a alguien
      v_monto := COALESCE(r.monto_pagado, 0);
      v_ref   := r.referencia;

      IF p_aplicar THEN
        IF v_monto > 0 THEN
          -- El pago sigue a la persona: se suma al equipo que se conserva.
          -- Si con eso queda cubierto, el equipo pasa a confirmado y se le
          -- apaga el reloj — si no, el panel lo seguiría llamando "reserva
          -- sin pago" y saldría en rojo con el dinero ya en la mano.
          -- Un cupo comprado sin pareja se queda en 'esperando_companero':
          -- está pagado, pero todavía le falta con quién jugar.
          UPDATE public.insc_equipos k
             SET monto_pagado = COALESCE(k.monto_pagado, 0) + v_monto,
                 pagado       = (COALESCE(k.monto_pagado, 0) + v_monto) >= k.costo AND k.costo > 0,
                 estado       = CASE WHEN k.estado = 'reservado'
                                      AND (COALESCE(k.monto_pagado, 0) + v_monto) >= k.costo
                                      AND k.costo > 0
                                     THEN 'confirmado' ELSE k.estado END,
                 reserva_expira = CASE WHEN (COALESCE(k.monto_pagado, 0) + v_monto) >= k.costo
                                        AND k.costo > 0
                                       THEN NULL ELSE k.reserva_expira END,
                 referencia   = COALESCE(k.referencia, v_ref),
                 notas        = COALESCE(k.notas || ' | ', '')
                                || 'Pago de $' || v_monto || ' trasladado del equipo #' || r.id
                                || COALESCE(' (ref ' || v_ref || ')', ''),
                 updated_at   = NOW()
           WHERE k.id = v_dueno;
        END IF;

        UPDATE public.insc_equipos
           SET estado       = 'cancelado',
               monto_pagado = 0,
               pagado       = FALSE,
               reserva_expira = NULL,
               notas        = COALESCE(notas || ' | ', '')
                              || 'Duplicado de ' || v_choque || '; se conserva el equipo #' || v_dueno
                              || CASE WHEN v_monto > 0 THEN ', pago trasladado allí' ELSE '' END,
               updated_at   = NOW()
         WHERE id = r.id;
      END IF;

      accion           := CASE WHEN p_aplicar THEN 'cancelado' ELSE 'se cancelaría' END;
      equipo_id        := r.id;
      equipo           := r.cap_nombre || ' / ' || COALESCE(r.comp_nombre, '(por definir)');
      inscrito         := r.created_at;
      estado_actual    := r.estado;
      jugador_repetido := v_choque;
      conserva_id      := v_dueno;
      pago_movido      := NULLIF(v_monto, 0);
      RETURN NEXT;
    END IF;
  END LOOP;

  -- Cupos que se hayan liberado pasan a quien esté en espera
  IF p_aplicar THEN
    PERFORM public.insc_equipos_liberar(p_torneo);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.insc_equipos_deduplicar(TEXT, BOOLEAN) TO authenticated;


-- ── ENSAYO EN SECO — no cambia nada. Revisa las filas "se cancelaría". ──────
SELECT * FROM public.insc_equipos_deduplicar('Copa Olímpica 2026')
 ORDER BY inscrito, equipo_id;

-- ── Cuando estés conforme, corre esto: ─────────────────────────────────────
-- SELECT * FROM public.insc_equipos_deduplicar('Copa Olímpica 2026', true)
--  ORDER BY inscrito, equipo_id;
