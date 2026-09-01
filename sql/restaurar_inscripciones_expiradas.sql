-- ============================================================================
--  FPTM — Restaurar inscripciones que expiraron solas
--  Correr en: Supabase → SQL Editor, una vez, después de create_insc_equipos.sql
--
--  Hasta ahora una reserva sin pagar pasaba sola a 'expirado' a las 48 h y
--  soltaba su cupo. La federación decidió que eso no vuelva a pasar: nadie
--  pierde su inscripción sin que una persona lo mande. Este script devuelve
--  a la vida las que ya se hubieran expirado.
--
--  Qué NO toca: las canceladas. Un 'cancelado' lo puso alguien a propósito,
--  y revivirlo sería deshacer una decisión de la federación.
--
--  Es seguro re-ejecutarlo: la segunda vez no encuentra nada que restaurar.
--
--  Reparto de cupo: se restauran por orden de inscripción. Quien quepa en su
--  división vuelve a su estado anterior; si la división ya se llenó mientras
--  tanto, el equipo vuelve como lista de espera en vez de pasarse del cupo.
--
--  ⚠ ANTES CORRE sql/deduplicar_inscripciones.sql
--  Mucha gente cuya reserva se expiró volvió a inscribirse — era legal, porque
--  una fila expirada no cuenta como activa. Al revivir la vieja, esa persona
--  queda en dos equipos. Por eso este script llama a insc_equipos_deduplicar()
--  al terminar: conserva la inscripción MÁS ANTIGUA de cada jugador y cancela
--  las posteriores, trasladando cualquier pago al equipo que se queda.
--  Esa función vive en el otro archivo, así que ese va primero.
-- ============================================================================

WITH ocupacion AS (
  SELECT torneo, division, COUNT(*) AS ocupados
    FROM public.insc_equipos
   WHERE public.insc_equipo_ocupa_cupo(estado)
   GROUP BY torneo, division
),
candidatos AS (
  SELECT e.id, e.torneo, e.division, e.comp_nombre, e.cap_nombre,
         ROW_NUMBER() OVER (PARTITION BY e.torneo, e.division
                            ORDER BY e.created_at, e.id) AS turno
    FROM public.insc_equipos e
   WHERE e.estado = 'expirado'
),
plan AS (
  SELECT c.id, c.torneo, c.cap_nombre, c.division,
         -- Un equipo sin compañero era un cupo comprado en solitario
         CASE WHEN COALESCE(o.ocupados, 0) + c.turno <= COALESCE(d.max_equipos, 999999)
              THEN CASE WHEN c.comp_nombre IS NULL THEN 'esperando_companero' ELSE 'reservado' END
              ELSE 'lista_espera' END AS estado_nuevo
    FROM candidatos c
    LEFT JOIN ocupacion o ON o.torneo = c.torneo AND o.division  IS NOT DISTINCT FROM c.division
    LEFT JOIN public.insc_divisiones d ON d.torneo = c.torneo AND d.division = c.division
),
restaurados AS (
  UPDATE public.insc_equipos e
     SET estado = p.estado_nuevo,
         -- Se les da una ventana de pago nueva; ya no expira sola, pero el
         -- panel la usa para saber desde cuándo se les debe perseguir.
         reserva_expira = CASE WHEN p.estado_nuevo = 'lista_espera' THEN NULL
                               ELSE NOW() + (public.insc_equipos_reserva_horas() || ' hours')::INTERVAL END,
         updated_at = NOW()
    FROM plan p
   WHERE e.id = p.id
  RETURNING e.id, e.cap_nombre, e.comp_nombre, e.division, e.estado
)
SELECT id,
       cap_nombre || ' / ' || COALESCE(comp_nombre, '(por definir)') AS equipo,
       COALESCE(division, 'sin división') AS division,
       estado AS restaurado_como
  FROM restaurados
 ORDER BY division, id;


-- ---------------------------------------------------------------------------
-- Y ahora se quitan los duplicados que la restauración pueda haber creado.
-- Manda la inscripción más antigua; el dinero de las canceladas se traslada.
-- Revisa este informe: las filas 'cancelado' son las que se dieron de baja.
-- ---------------------------------------------------------------------------
SELECT * FROM public.insc_equipos_deduplicar('Copa Olímpica 2026', true)
 WHERE accion <> 'conservar'
 ORDER BY inscrito, equipo_id;
