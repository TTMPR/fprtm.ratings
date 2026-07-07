-- ============================================================
--  FPTM — Restaurar clubs de jugadores ECEDAO
--  Recuperado desde insc_registro donde club_registro = "Ciudad - ECEDAO"
--  Ejecutar en: Supabase → SQL Editor
-- ============================================================

-- Ceiba Marlins
UPDATE "Base de Datos" SET "Club" = 'Ceiba Marlins'
  WHERE "Member ID" IN (16175, 87128);
  -- April Cintron Matos, Sofia Diaz Nunez

-- Club Bravos de Cidra
UPDATE "Base de Datos" SET "Club" = 'Club Bravos de Cidra'
  WHERE "Member ID" IN (24621, 57576, 79514, 85574, 57400);
  -- Arana Hernandez, Derick Ortiz, Fabian Ortiz, Kariana Pacheco, Sebastian Pedraza

-- Academia de TM Yabucoa
UPDATE "Base de Datos" SET "Club" = 'Academia de TM Yabucoa'
  WHERE "Member ID" IN (84341);
  -- Ariana Aponte Rivera

-- San Juan Table Tennis Club
UPDATE "Base de Datos" SET "Club" = 'San Juan Table Tennis Club'
  WHERE "Member ID" IN (19358, 45382);
  -- Aurora Bonome Burgos, Brianna Rodriguez Marrero

-- Villalba
UPDATE "Base de Datos" SET "Club" = 'Villalba'
  WHERE "Member ID" IN (92240);
  -- Elier Hernandez Torres

-- Aguilas de la Montaña Utuado
UPDATE "Base de Datos" SET "Club" = 'Aguilas de la Montaña Utuado'
  WHERE "Member ID" IN (56025, 19287);
  -- Hector Torres Montero, Leilanisbet Vega Borrero

-- Morovis Table Tennis Club
UPDATE "Base de Datos" SET "Club" = 'Morovis Table Tennis Club'
  WHERE "Member ID" IN (74686);
  -- Isabella Castro Perez

-- Añasco
UPDATE "Base de Datos" SET "Club" = 'Añasco'
  WHERE "Member ID" IN (35112);
  -- Kailani Cruz Martell

-- Caballetes de Corozal
UPDATE "Base de Datos" SET "Club" = 'Caballetes de Corozal'
  WHERE "Member ID" IN (38016, 49117);
  -- Karellys Rosado Rodriguez, Taviana Burgos Morales

-- Tenis de Mesa Humacao
UPDATE "Base de Datos" SET "Club" = 'Tenis de Mesa Humacao'
  WHERE "Member ID" IN (60432);
  -- Gabriel Gomez Quiroz

-- ⚠️  Cayey (member 20458 - Alejandro Torres Mercado)
-- "Cayey" no está en la lista oficial de clubs.
-- Descomenta la línea correcta:
-- UPDATE "Base de Datos" SET "Club" = 'Cayey' WHERE "Member ID" = 20458;
-- UPDATE "Base de Datos" SET "Club" = 'Barranquitas' WHERE "Member ID" = 20458;

-- Verificar resultado
SELECT "Member ID", "Club", "Escuela"
FROM "Base de Datos"
WHERE "Member ID" IN (20458,16175,24621,84341,19358,45382,57576,92240,79514,60432,56025,74686,35112,38016,85574,19287,57400,87128,49117)
ORDER BY "Club", "Member ID";
