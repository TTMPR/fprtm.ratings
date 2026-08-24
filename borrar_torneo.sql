-- ============================================================
--  FPTM — Borrar un torneo por nombre (definitivo)
--  Ejecutar en: Supabase → SQL Editor
--
--  Revierte los ratings al valor previo al torneo y borra sus
--  partidos, snapshots y el torneo mismo. Úsalo cuando el botón
--  de la papelera en la app no baste.
--
--  ⚠ Cambia el nombre en la línea de abajo antes de ejecutar.
-- ============================================================

DO $$
DECLARE
    v_nombre  CONSTANT TEXT := 'TEST BORRAR';   -- ← nombre exacto del torneo
    v_id      INTEGER;
    v_n       INTEGER;
BEGIN
    SELECT id INTO v_id FROM torneos WHERE nombre = v_nombre;

    IF v_id IS NULL THEN
        RAISE NOTICE 'No existe un torneo llamado "%" — nada que borrar.', v_nombre;
        RETURN;
    END IF;
    RAISE NOTICE 'Torneo "%" encontrado (id %)', v_nombre, v_id;

    -- 1. Revertir ratings al valor con que los jugadores llegaron al torneo
    UPDATE "Base de Datos" bd
    SET    "New Rating" = re.rating_inicio
    FROM   resultados_evento re
    WHERE  re.id_torneo = v_id
      AND  bd."Member ID" = re.id_jugador;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE '  % rating(s) revertido(s) en Base de Datos', v_n;

    UPDATE jugadores j
    SET    rating_actual = re.rating_inicio
    FROM   resultados_evento re
    WHERE  re.id_torneo = v_id
      AND  j.id = re.id_jugador;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE '  % rating(s) revertido(s) en jugadores', v_n;

    -- 2. Borrar los datos del torneo
    DELETE FROM partidos WHERE torneo_id = v_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE '  % partido(s) borrado(s)', v_n;

    DELETE FROM resultados_evento WHERE id_torneo = v_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE '  % snapshot(s) borrado(s)', v_n;

    DELETE FROM torneos WHERE id = v_id;
    RAISE NOTICE '✅ Torneo "%" eliminado.', v_nombre;
END $$;

-- Verificar que ya no está
SELECT id, nombre, fecha FROM torneos ORDER BY fecha DESC LIMIT 10;
