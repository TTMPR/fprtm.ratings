-- ============================================================
--  FPRTM — Carga 1700 Under — Albergue Olímpico Open 2026
--  Pegar y ejecutar en: Supabase → SQL Editor
-- ============================================================

DO $$
DECLARE
    v_torneo_id     INTEGER;
    v_torneo_nombre CONSTANT TEXT := 'Albergue Olímpico Open 2026';
    v_torneo_fecha  CONSTANT DATE := '2026-03-01';
    r               RECORD;
    v_diff          INTEGER;
    v_pts           INTEGER;
    v_winner_fav    BOOLEAN;
    v_saved         INTEGER := 0;
    v_skipped       INTEGER := 0;
    v_updated       INTEGER := 0;
BEGIN

-- ── 1. Crear o reutilizar torneo ──────────────────────────────
    SELECT id INTO v_torneo_id FROM torneos WHERE nombre = v_torneo_nombre;
    IF v_torneo_id IS NULL THEN
        INSERT INTO torneos (nombre, fecha)
        VALUES (v_torneo_nombre, v_torneo_fecha)
        RETURNING id INTO v_torneo_id;
        RAISE NOTICE 'Torneo creado con ID: %', v_torneo_id;
    ELSE
        RAISE NOTICE 'Usando torneo existente ID: %', v_torneo_id;
    END IF;

-- ── 2. Tabla temporal con todos los partidos ──────────────────
    DROP TABLE IF EXISTS _matches;
    DROP TABLE IF EXISTS _deltas;
    CREATE TEMP TABLE _matches (winner_id INT, loser_id INT) ON COMMIT DROP;
    INSERT INTO _matches (winner_id, loser_id) VALUES
-- Ronda de Grupos — B vs C
(71953,34914),(41850,76768),(34957,19099),(96374,57795),(98259,27154),
(41285,17944),(35112,86503),(40982,38534),(41195,97062),(27342,15817),
(85525,43386),(48890,11934),(59672,85914),
-- Ronda de Grupos — A vs B
(71953,40161),(41850,42493),(34957,25860),(95180,96374),(50857,98259),
(17944,65461),(35112,72296),(96474,40982),(19287,18834),(40007,41195),
(27342,87128),(38864,85525),(73699,11934),(57576,59672),
-- Ronda de Grupos — A vs C
(40161,34914),(42493,76768),(19099,25860),(95180,57795),(50857,27154),
(65461,41285),(72296,86503),(96474,38534),(40007,97062),(87128,15817),
(38864,43386),(73699,48890),(57576,85914),
-- Round of 64
(86503,17944),(98259,97062),(40982,15817),(48890,76768),(25860,85914),
(57795,11934),(59672,34914),(43386,72296),(27154,38534),
-- Round of 32
(57576,86503),(18834,85525),(98259,41850),(40982,34957),(65461,48890),
(96374,27342),(40161,40007),(35112,25860),(96474,57795),(19287,42493),
(19099,38864),(50857,59672),(95180,43386),(71953,41285),(41195,87128),
(73699,27154),
-- Round of 16
(18834,57576),(40982,98259),(65461,96374),(35112,40161),(19287,96474),
(50857,19099),(95180,71953),(73699,41195);

-- ── 3. Tabla de deltas acumulados por jugador ─────────────────
    CREATE TEMP TABLE _deltas (
        player_id INT PRIMARY KEY,
        delta     INT DEFAULT 0,
        wins      INT DEFAULT 0,
        losses    INT DEFAULT 0
    ) ON COMMIT DROP;

    INSERT INTO _deltas (player_id)
    SELECT DISTINCT id FROM (
        SELECT winner_id AS id FROM _matches
        UNION
        SELECT loser_id  AS id FROM _matches
    ) x;

-- ── 4. Calcular puntos e insertar partidos ────────────────────
    FOR r IN
        SELECT
            m.winner_id,
            m.loser_id,
            COALESCE(w."New Rating", w."Rating", 1500) AS rW,
            COALESCE(l."New Rating", l."Rating", 1500) AS rL,
            (w."Member ID" IS NOT NULL) AS w_found,
            (l."Member ID" IS NOT NULL) AS l_found
        FROM _matches m
        LEFT JOIN "Base de Datos" w ON w."Member ID" = m.winner_id
        LEFT JOIN "Base de Datos" l ON l."Member ID" = m.loser_id
    LOOP
        IF NOT r.w_found OR NOT r.l_found THEN
            RAISE NOTICE 'ID no encontrado — winner: % (%), loser: % (%)',
                r.winner_id, r.w_found, r.loser_id, r.l_found;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        -- Tabla de puntos FPRTM
        v_diff       := ABS(r.rW - r.rL);
        v_winner_fav := r.rW >= r.rL;

        IF    v_diff <=  24 THEN v_pts := 8;
        ELSIF v_diff <=  49 THEN v_pts := CASE WHEN v_winner_fav THEN  7 ELSE 10 END;
        ELSIF v_diff <=  99 THEN v_pts := CASE WHEN v_winner_fav THEN  5 ELSE 12 END;
        ELSIF v_diff <= 149 THEN v_pts := CASE WHEN v_winner_fav THEN  3 ELSE 15 END;
        ELSIF v_diff <= 199 THEN v_pts := CASE WHEN v_winner_fav THEN  2 ELSE 20 END;
        ELSIF v_diff <= 249 THEN v_pts := CASE WHEN v_winner_fav THEN  1 ELSE 26 END;
        ELSE                     v_pts := CASE WHEN v_winner_fav THEN  0 ELSE 32 END;
        END IF;

        -- Acumular deltas
        UPDATE _deltas SET delta = delta + v_pts, wins   = wins   + 1 WHERE player_id = r.winner_id;
        UPDATE _deltas SET delta = delta - v_pts, losses = losses + 1 WHERE player_id = r.loser_id;

        -- Insertar partido
        INSERT INTO partidos (
            torneo_id, jugador_a_id, jugador_b_id, ganador_id,
            rating_a_antes, rating_b_antes,
            rating_a_despues, rating_b_despues,
            puntos_a, puntos_b,
            categoria_evento, fecha
        ) VALUES (
            v_torneo_id, r.winner_id, r.loser_id, r.winner_id,
            r.rW, r.rL,
            r.rW + v_pts, r.rL - v_pts,
            v_pts, -v_pts,
            '1700 Under', v_torneo_fecha
        );

        v_saved := v_saved + 1;
    END LOOP;

    RAISE NOTICE '✅ Partidos guardados: %,  omitidos (ID no encontrado): %', v_saved, v_skipped;

-- ── 5. Actualizar New Rating en Base de Datos ─────────────────
    UPDATE "Base de Datos" bd
    SET "New Rating" = COALESCE(bd."New Rating", bd."Rating", 1500) + d.delta
    FROM _deltas d
    WHERE bd."Member ID" = d.player_id
      AND d.delta <> 0;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RAISE NOTICE '✅ Ratings actualizados: %', v_updated;

-- ── 6. Snapshot resultados_evento ─────────────────────────────
    INSERT INTO resultados_evento (
        id_jugador, nombre, club,
        rating_inicio, rating_fin,
        ganados, perdidos,
        id_torneo
    )
    SELECT
        d.player_id,
        TRIM(COALESCE(bd."First Name",'') || ' ' || COALESCE(bd."Last Name",'')),
        '',
        COALESCE(bd."New Rating", bd."Rating", 1500) - d.delta,
        COALESCE(bd."New Rating", bd."Rating", 1500),
        d.wins,
        d.losses,
        v_torneo_id
    FROM _deltas d
    JOIN "Base de Datos" bd ON bd."Member ID" = d.player_id
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '✅ Snapshots resultados_evento: %', (SELECT COUNT(*) FROM _deltas WHERE wins+losses > 0);

END;
$$;
