-- ============================================================
--  FPRTM — Carga Albergue Olímpico 2026
--  Pegar y ejecutar en: Supabase → SQL Editor
-- ============================================================

DO $$
DECLARE
    v_torneo_id    INTEGER;
    v_torneo_nombre CONSTANT TEXT := 'Albergue Olímpico 2026';
    v_torneo_fecha  CONSTANT DATE := '2026-03-01';
    r              RECORD;
    v_diff         INTEGER;
    v_pts          INTEGER;
    v_winner_fav   BOOLEAN;
    v_saved        INTEGER := 0;
    v_skipped      INTEGER := 0;
    v_updated      INTEGER := 0;
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
    CREATE TEMP TABLE _matches (winner_id INT, loser_id INT) ON COMMIT DROP;
    INSERT INTO _matches (winner_id, loser_id) VALUES
(14207,39871),(14207,51347),(39871,32431),(14207,56566),(51347,40021),(32431,89840),(39871,45382),(56566,95909),(14207,83000),(40021,99593),
(51347,16175),(32431,28726),(89840,17331),(45382,88172),(39871,51245),(16175,37869),(28726,30969),(89840,18675),(56566,58520),(83000,76540),
(40021,31417),(51245,84341),(65610,30866),(39154,26683),(36158,48752),(62743,39831),(19099,91678),(97900,53025),(15817,99065),(86099,78146),
(17331,88172),(40021,30969),(14207,16175),(28726,18675),(51347,37869),(95909,51245),(13248,30866),(39154,97806),(39831,66057),(19099,27146),
(93136,53025),(37607,99065),(86099,81200),(45382,83000),(17331,31417),(32431,40021),(14207,89840),(99593,18675),(51347,56566),(58520,51245),
(13248,65610),(97806,26683),(81200,78146),(45382,76540),(88172,31417),(32431,30969),(89840,16175),(99593,28726),(37869,56566),(95909,58520),
(39871,84341),(48752,19099),(48752,30866),(19099,61876),(30866,34914),(48752,37607),(19099,39831),(61876,36158),(34914,86099),(30866,65610),
(48752,62743),(37607,78146),(39831,97900),(19099,97806),(36158,13248),(61876,81200),(78146,27146),(39831,99065),(97806,53025),(36158,26683),
(34914,93136),(65610,66057),(30866,39154),(48752,91678),(81200,15817),(62743,66057),(27146,91678),(97900,93136),(37607,15817),(61876,34914),
(28289,24592),(24592,54597),(28289,93810),(24592,37869),(57400,37869),(24592,28289),(54597,95181),(86503,66985),(69470,98259),(75612,97684),
(76542,19287),(33416,69177),(91959,87128),(57576,49117),(79514,72296),(99353,65444),(76540,21226),(28289,57400),(93810,95181),(66985,82512),
(60432,69470),(88172,75612),(65333,76542),(33416,30969),(91959,24371),(92240,49117),(16175,79514),(25014,99353),(76540,74686),(92240,33416),
(33416,65333),(92240,57447),(65333,76540),(33416,16175),(92240,74686),(57447,60432),(76540,24371),(65333,21226),(33416,25014),(16175,69470),
(92240,79514),(74686,91959),(60432,49117),(57447,76542),(69470,57576),(16175,98259),(92240,97684),(79514,66985),(74686,65444),(91959,30969),
(49117,88172),(60432,72296),(76540,86503),(24371,75612),(21226,82512),(65333,87128),(33416,19287),(25014,52487),(76542,69177),(57447,99353),
(28289,37869),(24592,57400),(93810,54597),(82512,86503),(60432,98259),(88172,97684),(65333,19287),(69177,30969),(24371,87128),(92240,57576),
(16175,72296),(65444,25014),(74686,21226),(57447,52487),(71953,34914),(41850,76768),(34957,19099),(96374,57795),(98259,27154),(41285,17944),
(35112,86503),(40982,38534),(41195,97062),(27342,15817),(85525,43386),(48890,11934),(59672,85914),(90676,42772),(84593,79983),(33583,90854),
(92264,81020),(60523,21847),(63279,43130),(36306,27578),(71953,40161),(41850,42493),(34957,25860),(95180,96374),(50857,98259),(17944,65461),
(35112,72296),(96474,40982),(19287,18834),(40007,41195),(27342,87128),(38864,85525),(73699,11934),(57576,59672),(90676,32810),(39007,81020),
(69929,21847),(63264,43130),(97153,36306),(40161,34914),(42493,76768),(19099,25860),(95180,57795),(50857,27154),(65461,41285),(72296,86503),
(96474,38534),(40007,97062),(87128,15817),(38864,43386),(73699,48890),(57576,85914),(42772,32810),(39007,92264),(69929,60523),(63279,63264),
(27578,97153),(74515,49240),(63279,69929),(63279,27578),(69929,74515),(27578,42772),(63279,92264),(69929,39007),(74515,79983),(27578,49240),
(42772,84593),(92264,33583),(63279,60523),(69929,63264),(39007,90854),(79983,90676),(74515,36306),(63264,81020),(49240,43130),(36306,97153),
(80678,97900),(80678,69929),(97900,82512),(80678,78146),(69929,32810),(97900,38016),(82512,84593),(84593,63264),(97900,84593),(32810,78146),
(57576,50857),(95180,90676),(48752,15075),(63354,13617),(51347,85674),(32431,19358),(69929,38016),(82512,78146),(50857,42772),(57576,27578),
(79514,95180),(60432,15075),(92240,13617),(30379,85674),(24592,19358),(80678,84593),(82512,32810),(50857,27578),(70637,49363),(49363,69638),
(70637,97410),(49363,11025),(97410,50001),(79514,60432),(60432,63354),(79514,50857),(57576,95180),(92240,48752),(63354,15075),(50857,90676),
(79514,42772),(95180,27578),(48752,13617),(24592,85674),(85674,30379),(85674,32431),(19358,51347),(38016,63264),(57576,42772),(79514,90676),
(60432,48752),(92240,63354),(30379,51347),(24592,32431),(57400,99166),(99166,88504),(57400,83000),(88504,86099),(83000,63883),(28301,59009),
(59009,72296),(28301,34957),(59009,65461),(56025,26683),(26683,21420),(56025,98777),(21420,36387),(10074,19305),(19305,25860),(10074,77391),
(19305,44795),(25860,53404),(77391,94080),(10074,92264),(92264,65108),(14207,84341),(84341,19358),(14207,45382),(19358,49117),(84341,87128),
(14207,74686),(45382,71953),(49117,40007),(87128,16175),(84341,86503),(14207,49321),(74686,98259),(71953,93748),(84847,38016),(38016,22224),
(84847,80468),(22224,85914),(77391,92264),(94080,65108),(53404,44795),(72296,34957),(16175,49321),(49117,86503),(93748,98259),(71953,87128),
(25860,77391),(19305,94080),(10074,53404),(72296,59009),(74686,16175),(14207,49117),(84341,93748),(19358,87128),(25860,92264),(19305,65108),
(10074,44795),(34957,59009),(28301,65461),(74686,49321),(14207,86503),(84341,98259),(19358,71953),(45382,40007),(99166,86099),(88504,63883),
(98777,36387),(69638,97410),(49363,50001),(38016,80468),(99166,83000),(57400,88504),(26683,98777),(69638,11025),(70637,50001),(83000,86099),
(57400,63883),(26683,36387),(56025,21420),(97410,11025),(80468,22224),(84847,85914);

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
            TRIM(COALESCE(w."First Name",'') || ' ' || COALESCE(w."Last Name",'')) AS nameW,
            TRIM(COALESCE(l."First Name",'') || ' ' || COALESCE(l."Last Name",'')) AS nameL,
            (w."Member ID" IS NOT NULL) AS w_found,
            (l."Member ID" IS NOT NULL) AS l_found
        FROM _matches m
        LEFT JOIN "Base de Datos" w ON w."Member ID" = m.winner_id
        LEFT JOIN "Base de Datos" l ON l."Member ID" = m.loser_id
    LOOP
        IF NOT r.w_found OR NOT r.l_found THEN
            RAISE NOTICE 'ID no encontrado en BD — winner: % (%), loser: % (%)',
                r.winner_id, r.w_found, r.loser_id, r.l_found;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        -- Tabla de puntos FPRTM
        v_diff      := ABS(r.rW - r.rL);
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
            fecha
        ) VALUES (
            v_torneo_id, r.winner_id, r.loser_id, r.winner_id,
            r.rW, r.rL,
            r.rW + v_pts, r.rL - v_pts,
            v_pts, -v_pts,
            v_torneo_fecha
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

-- ── 6. Snapshot resultados_evento ────────────────────────────
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
    JOIN "Base de Datos" bd ON bd."Member ID" = d.player_id;

    RAISE NOTICE '✅ Snapshots resultados_evento: %', (SELECT COUNT(*) FROM _deltas WHERE wins+losses > 0);

END;
$$;
