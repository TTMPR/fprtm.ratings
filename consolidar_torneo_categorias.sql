-- ============================================================
--  FPTM — Consolidar un torneo partido en una fila por categoría
--  Ejecutar en: Supabase → SQL Editor
--
--  carga_todos_eventos_2026.sql creó un registro de torneo por cada
--  evento ("Albergue Olímpico 2026 — 1700 Under", "… — 9U - Femenino",
--  etc.). La app los agrupa por el nombre, pero en la base son filas
--  distintas y eso complica los reportes y el relleno histórico.
--
--  Este script:
--    1. Rescata la categoría desde el nombre y la guarda en
--       partidos.categoria (solo si está vacía).
--    2. Deja la fila de menor id como el torneo real, con el nombre base.
--    3. Reapunta partidos y snapshots a esa fila.
--    4. Borra las filas sobrantes.
--
--  No toca ratings: solo reorganiza a qué torneo pertenece cada partido.
--
--  ⚠ Requiere haber corrido antes add_categoria_partidos.sql.
-- ============================================================

DO $$
DECLARE
    v_base   CONSTANT TEXT := 'Albergue Olímpico 2026';  -- ← nombre base
    v_sep    CONSTANT TEXT := ' — ';                      -- guion largo (em dash)
    v_destino INTEGER;
    r         RECORD;
    v_n       INTEGER;
    v_total   INTEGER := 0;
BEGIN
    -- 1. Guardar la categoría de cada fila en sus partidos
    FOR r IN
        SELECT id, nombre FROM torneos
        WHERE nombre = v_base OR nombre LIKE v_base || v_sep || '%'
        ORDER BY id
    LOOP
        IF position(v_sep in r.nombre) > 0 THEN
            UPDATE partidos
            SET    categoria = split_part(r.nombre, v_sep, 2)
            WHERE  torneo_id = r.id
              AND (categoria IS NULL OR categoria = '');
            GET DIAGNOSTICS v_n = ROW_COUNT;
            IF v_n > 0 THEN
                RAISE NOTICE '  % → categoría "%" en % partido(s)',
                    r.nombre, split_part(r.nombre, v_sep, 2), v_n;
            END IF;
        END IF;
    END LOOP;

    -- 2. La fila más antigua se queda como el torneo real
    SELECT id INTO v_destino FROM torneos
    WHERE nombre = v_base OR nombre LIKE v_base || v_sep || '%'
    ORDER BY id
    LIMIT 1;

    IF v_destino IS NULL THEN
        RAISE NOTICE 'No se encontró ningún torneo que empiece con "%" — nada que hacer.', v_base;
        RETURN;
    END IF;

    UPDATE torneos SET nombre = v_base WHERE id = v_destino;
    RAISE NOTICE 'Torneo destino: id % ("%")', v_destino, v_base;

    -- 3. Reapuntar todo lo demás al destino
    FOR r IN
        SELECT id, nombre FROM torneos
        WHERE (nombre = v_base OR nombre LIKE v_base || v_sep || '%')
          AND id <> v_destino
        ORDER BY id
    LOOP
        UPDATE partidos          SET torneo_id = v_destino WHERE torneo_id = r.id;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_total := v_total + v_n;

        UPDATE resultados_evento SET id_torneo = v_destino WHERE id_torneo = r.id;

        DELETE FROM torneos WHERE id = r.id;
        RAISE NOTICE '  fusionado: "%" (% partidos)', r.nombre, v_n;
    END LOOP;

    RAISE NOTICE '✅ Consolidado. % partido(s) reapuntados al torneo %.', v_total, v_destino;
END $$;

-- Verificar: debe quedar una sola fila, con todos sus partidos y categorías
SELECT t.id, t.nombre, t.fecha, t.publicado,
       (SELECT count(*) FROM partidos p WHERE p.torneo_id = t.id)                        AS partidos,
       (SELECT count(DISTINCT p.categoria) FROM partidos p WHERE p.torneo_id = t.id)     AS categorias
FROM torneos t
WHERE t.nombre LIKE 'Albergue Olímpico 2026%'
ORDER BY t.id;
