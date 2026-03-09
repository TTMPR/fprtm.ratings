-- ============================================================
--  PASO 1: Borrar torneo "Albergue Olímpico 2026 Rev" y
--          revertir los New Rating aplicados.
--  Ejecutar ANTES de carga_open_2026.sql
-- ============================================================

DO $$
DECLARE
    v_torneo_id INTEGER;
    v_updated   INTEGER;
BEGIN
    SELECT id INTO v_torneo_id
    FROM torneos WHERE nombre = 'Albergue Olímpico 2026 Rev';

    IF v_torneo_id IS NULL THEN
        RAISE NOTICE 'Torneo "Albergue Olímpico 2026 Rev" no encontrado — nada que borrar.';
        RETURN;
    END IF;

    RAISE NOTICE 'Revirtiendo torneo ID: %', v_torneo_id;

    -- 1. Revertir New Rating
    UPDATE "Base de Datos" bd
    SET "New Rating" = "New Rating" - (re.rating_fin - re.rating_inicio)
    FROM resultados_evento re
    WHERE re.id_torneo = v_torneo_id
      AND re.id_jugador = bd."Member ID";

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RAISE NOTICE '✅ Ratings revertidos: %', v_updated;

    -- 2. Borrar partidos, snapshots y torneo
    DELETE FROM partidos         WHERE torneo_id  = v_torneo_id;
    DELETE FROM resultados_evento WHERE id_torneo = v_torneo_id;
    DELETE FROM torneos           WHERE id         = v_torneo_id;

    RAISE NOTICE '✅ Torneo Rev borrado completamente.';
END;
$$;
