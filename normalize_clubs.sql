-- ============================================================
--  FPTM — Normalización de nombres de clubes y escuelas
--  Ejecutar en: Supabase → SQL Editor
--  Primero asegúrate de haber agregado la columna Escuela:
--    ALTER TABLE "Base de Datos" ADD COLUMN IF NOT EXISTS "Escuela" TEXT;
-- ============================================================

-- 1. Detectar y mover escuelas al campo Escuela (donde Club tiene el nombre)
UPDATE "Base de Datos"
SET "Escuela" = 'ECEDAO', "Club" = NULL
WHERE LOWER(TRIM("Club")) ILIKE '%ecedao%'
  AND ("Escuela" IS NULL OR "Escuela" = '');

UPDATE "Base de Datos"
SET "Escuela" = 'FMC', "Club" = NULL
WHERE LOWER(TRIM("Club")) ~ '\yfmc\y'
  AND ("Escuela" IS NULL OR "Escuela" = '');

UPDATE "Base de Datos"
SET "Escuela" = 'Escuela de Deportes de San Juan', "Club" = NULL
WHERE ("Club" ILIKE '%ed san juan%' OR "Club" ILIKE '%deportes san juan%' OR "Club" ILIKE '%ed. san juan%')
  AND ("Escuela" IS NULL OR "Escuela" = '');

UPDATE "Base de Datos"
SET "Escuela" = 'Escuela de Deportes de Carolina', "Club" = NULL
WHERE ("Club" ILIKE '%ed carolina%' OR "Club" ILIKE '%deportes carolina%' OR "Club" ILIKE '%ed. carolina%')
  AND ("Escuela" IS NULL OR "Escuela" = '');

-- 2. Normalizar nombres de clubes a nombres oficiales
UPDATE "Base de Datos" SET "Club" = 'Ceiba Marlins'
  WHERE "Club" ILIKE '%ceiba%' AND "Club" NOT ILIKE '%ecedao%';

UPDATE "Base de Datos" SET "Club" = 'Tenis de Mesa Humacao'
  WHERE "Club" ILIKE '%humacao%';

UPDATE "Base de Datos" SET "Club" = 'Academia de TM Yabucoa'
  WHERE "Club" ILIKE '%yabucoa%';

UPDATE "Base de Datos" SET "Club" = 'CAM Caguas'
  WHERE "Club" ILIKE '%caguas%';

UPDATE "Base de Datos" SET "Club" = 'Guaynabo'
  WHERE LOWER(TRIM("Club")) IN ('guaynabo', 'tt guaynabo', 'table tennis guaynabo');

UPDATE "Base de Datos" SET "Club" = 'San Juan Table Tennis Club'
  WHERE "Club" ILIKE '%san juan%'
    AND "Club" NOT ILIKE '%deportes%' AND "Club" NOT ILIKE '%ed%';

UPDATE "Base de Datos" SET "Club" = 'Club Tenis de Mesa Trujillo Alto'
  WHERE "Club" ILIKE '%trujillo%';

UPDATE "Base de Datos" SET "Club" = 'Club Bravos de Cidra'
  WHERE "Club" ILIKE '%cidra%' OR "Club" ILIKE '%bravos%';

UPDATE "Base de Datos" SET "Club" = 'Aguilas de la Montaña Utuado'
  WHERE "Club" ILIKE '%utuado%' OR "Club" ILIKE '%aguilas%';

UPDATE "Base de Datos" SET "Club" = 'Morovis Table Tennis Club'
  WHERE "Club" ILIKE '%morovis%';

UPDATE "Base de Datos" SET "Club" = 'Barranquitas'
  WHERE LOWER(TRIM("Club")) IN ('barranquitas', 'tt barranquitas', 'club barranquitas');

UPDATE "Base de Datos" SET "Club" = 'Caballetes de Corozal'
  WHERE "Club" ILIKE '%corozal%' OR "Club" ILIKE '%caballetes%';

UPDATE "Base de Datos" SET "Club" = 'Florida TTC'
  WHERE "Club" ILIKE '%florida%';

UPDATE "Base de Datos" SET "Club" = 'Mayaguez'
  WHERE "Club" ILIKE '%mayag%';

UPDATE "Base de Datos" SET "Club" = 'CFD Salinas'
  WHERE "Club" ILIKE '%salinas%';

UPDATE "Base de Datos" SET "Club" = 'Vega Baja Table Tennis Club'
  WHERE "Club" ILIKE '%vega baja%';

UPDATE "Base de Datos" SET "Club" = 'Bayamón'
  WHERE "Club" ILIKE '%bayam%';

UPDATE "Base de Datos" SET "Club" = 'Villalba'
  WHERE LOWER(TRIM("Club")) IN ('villalba', 'tt villalba', 'club villalba');

UPDATE "Base de Datos" SET "Club" = 'Añasco'
  WHERE "Club" ILIKE '%añasco%' OR "Club" ILIKE '%anasco%';

UPDATE "Base de Datos" SET "Club" = 'Naguabo Table Tennis Club'
  WHERE "Club" ILIKE '%naguabo%';

-- 3. Limpiar valores que significan "ninguno"
UPDATE "Base de Datos" SET "Club" = NULL
  WHERE LOWER(TRIM("Club")) IN ('ninguno', 'none', 'otro', 'other', 'n/a', 'na', '-', '--', '');

-- 4. Verificar resultados
SELECT "Club", "Escuela", COUNT(*) as jugadores
FROM "Base de Datos"
GROUP BY "Club", "Escuela"
ORDER BY jugadores DESC;
