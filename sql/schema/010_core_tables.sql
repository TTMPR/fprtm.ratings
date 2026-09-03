-- ============================================================================
-- 010 · Tablas núcleo — RECUPERADAS DE PRODUCCIÓN
--
-- Origen: extracción de sólo lectura del catálogo del proyecto de producción
-- (sql/schema/EXTRACT_PRODUCTION_SCHEMA.sql), ejecutada el 2026-09-03 contra
-- PostgreSQL 17.6. Nada aquí está inventado: cada tipo, default, restricción
-- e índice viene del volcado.
--
-- Estas cinco tablas no tenían CREATE TABLE en ningún fichero del
-- repositorio. Sustituye a 010_core_tables.PENDING.sql.
--
-- ⚠️  REPRODUCE PRODUCCIÓN TAL CUAL, INCLUIDOS SUS DEFECTOS.
--     Los dos más graves están anotados abajo (PK compuesta de "Base de
--     Datos", columnas duplicadas en partidos). NO se corrigen aquí: staging
--     debe empezar siendo igual que producción. Arreglarlos es trabajo
--     posterior, con decisión explícita.
-- ============================================================================


-- ============================================================================
-- "Base de Datos" — registro de jugadores y ratings oficiales   (619 filas)
-- ============================================================================
--
-- ⚠️  DEFECTO GRAVE: la clave primaria son DIEZ columnas, no "Member ID".
--
--     PRIMARY KEY ("Member ID","First Name","Last Name","Rating","Email",
--                  "Sex","Date of Birth","Expiration Date","Home Address","Club")
--
--     Consecuencias reales, no teóricas:
--       · "Member ID" NO es único. Nada impide dos filas con el mismo
--         Member ID y distinto Rating.
--       · Las diez columnas son NOT NULL: no se puede dar de alta a un
--         jugador sin correo ni dirección postal.
--       · Cambiar el rating de un jugador cambia su clave primaria.
--       · backup/restore_backup.mjs hace upsert con on_conflict=Member ID.
--         Como no existe restricción única sobre esa columna sola, PostgREST
--         lo rechaza: la restauración de esta tabla FALLARÍA. Nunca se ha
--         probado (ver docs/PHASE0_BACKUP_AND_STAGING.md, riesgo 2).
--
--     Se reproduce igual a propósito. Corregirlo toca la tabla más sensible
--     del sistema y necesita su propio plan.
--
-- Nota: NO existe columna photo_url. Las fotos viven en photo_requests y en
-- el bucket player-photos.

CREATE TABLE IF NOT EXISTS public."Base de Datos" (
  "Member ID"                                bigint  NOT NULL,
  "First Name"                               text    NOT NULL,
  "Last Name"                                text    NOT NULL,
  "Rating"                                   bigint  NOT NULL,
  "Email"                                    text    NOT NULL,
  "Sex"                                      text    NOT NULL,
  "Date of Birth"                            text    NOT NULL,
  "Expiration Date"                          text    NOT NULL,
  "Home Address"                             text    NOT NULL,
  "Club"                                     text    NOT NULL,
  "New Rating"                               numeric,
  rating_morovis_open_2026                   integer,
  rating_ceiba_open_2026                     integer,
  rating_albergue_olimpico_summer_open_2026  integer,
  "Escuela"                                  text,
  rating_cidra_open_2026                     integer,
  CONSTRAINT "Base de Datos_pkey" PRIMARY KEY
    ("Member ID", "First Name", "Last Name", "Rating", "Email",
     "Sex", "Date of Birth", "Expiration Date", "Home Address", "Club")
);

-- "Rating" es bigint pero "New Rating" es numeric. La app lee
-- `p['New Rating'] || p['Rating']`, así que el tipo efectivo del rating
-- vigente cambia según cuál esté poblada. Reproducido tal cual.


-- ============================================================================
-- jugadores — segundo registro de jugadores                     (537 filas)
-- ============================================================================
--
-- ⚠️  NO es un residuo vacío: tiene 537 filas, lectura pública y su propio
--     trigger de auditoría. Es un registro DISTINTO de "Base de Datos"
--     (619 filas), con su propio rating (`rating_actual`, default 1000) y
--     campos de la temporada 2025.
--
--     index.html no lo consulta en ninguna ruta activa. Coincide en número
--     con los 537 jugadores de restore_rating_backup.sql, lo que sugiere que
--     fue el origen de aquel snapshot.
--
--     Queda pendiente decidir si va a staging, se congela o se retira.
--     Ver docs/SCHEMA_MANIFEST.md.

CREATE TABLE IF NOT EXISTS public.jugadores (
  id                  uuid    NOT NULL DEFAULT gen_random_uuid(),
  nombre_completo     text    NOT NULL,
  nombre              text,
  inicial             text,
  apellido_paterno    text,
  apellido_materno    text,
  participo_2025      boolean,
  club                text,
  sexo                text,
  membresia_status    text,
  edad                integer,
  categoria           text,
  rating_inicio_2025  integer,
  rating_clasif_feb   integer,
  rating_actual       integer NOT NULL DEFAULT 1000,
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now(),
  CONSTRAINT jugadores_pkey PRIMARY KEY (id)
);


-- ============================================================================
-- torneos                                                         (6 filas)
-- ============================================================================
-- bigserial reproduce exactamente el default de producción
-- (nextval('torneos_id_seq')) y deja la secuencia como propietaria de id.

CREATE TABLE IF NOT EXISTS public.torneos (
  id          bigserial   NOT NULL,
  nombre      text        NOT NULL,
  fecha       date        NOT NULL,
  lugar       text,
  tipo        text,
  temporada   integer     DEFAULT 2026,
  notas       text,
  created_at  timestamptz DEFAULT now(),
  deleted_at  timestamptz,
  publicado   boolean     DEFAULT true,
  CONSTRAINT torneos_pkey PRIMARY KEY (id)
);


-- ============================================================================
-- partidos — partidos con ratings antes/después              (1,829 filas)
-- ============================================================================
--
-- ⚠️  Hay PARES DE COLUMNAS DUPLICADAS de distintas épocas:
--       categoria_evento  y  categoria   → la app escribe `categoria`
--       score             y  marcador    → la app escribe `marcador`
--       puntos_a/puntos_b               → la app no las escribe nunca
--     subirApplyRatings() sólo rellena la segunda de cada par. Las primeras
--     conservan datos históricos. Reproducido tal cual; consolidarlas es
--     trabajo posterior.

CREATE TABLE IF NOT EXISTS public.partidos (
  id                bigserial   NOT NULL,
  torneo_id         bigint,
  jugador_a_id      bigint,
  jugador_b_id      bigint,
  ganador_id        bigint,
  rating_a_antes    integer,
  rating_b_antes    integer,
  rating_a_despues  integer,
  rating_b_despues  integer,
  puntos_a          integer,
  puntos_b          integer,
  score             text,
  categoria_evento  text,
  fecha             date,
  created_at        timestamptz DEFAULT now(),
  notas             text,
  categoria         text,
  fase              text,
  ronda             text,
  grupo             text,
  marcador          text,
  orden             integer,
  deleted_at        timestamptz,
  publicado         boolean     DEFAULT true,
  CONSTRAINT partidos_pkey PRIMARY KEY (id),
  CONSTRAINT partidos_torneo_id_fkey FOREIGN KEY (torneo_id)
    REFERENCES public.torneos(id)
);

-- Índices de producción que no crea 020.
CREATE INDEX IF NOT EXISTS idx_partidos_jugador_a ON public.partidos (jugador_a_id);
CREATE INDEX IF NOT EXISTS idx_partidos_jugador_b ON public.partidos (jugador_b_id);
CREATE INDEX IF NOT EXISTS idx_partidos_torneo    ON public.partidos (torneo_id);

-- Nota: jugador_a_id, jugador_b_id y ganador_id NO tienen clave foránea
-- contra "Base de Datos" — no podrían tenerla, porque "Member ID" no es
-- único por sí solo (ver el defecto de la PK arriba).


-- ============================================================================
-- resultados_evento — resumen por jugador y torneo             (780 filas)
-- ============================================================================
-- id es IDENTITY ALWAYS, no serial. restore_backup.mjs no lo trata como
-- especial (sólo excluye el id de audit_log), así que una restauración que
-- incluya la columna id sería rechazada. Anotado para la Fase 1.1.

CREATE TABLE IF NOT EXISTS public.resultados_evento (
  id             bigint      GENERATED ALWAYS AS IDENTITY,
  id_torneo      bigint      NOT NULL,
  id_jugador     integer     NOT NULL,
  nombre         text        NOT NULL,
  club           text,
  rating_inicio  integer     NOT NULL,
  rating_fin     integer     NOT NULL,
  ganados        integer     DEFAULT 0,
  perdidos       integer     DEFAULT 0,
  created_at     timestamptz DEFAULT now(),
  deleted_at     timestamptz,
  publicado      boolean     DEFAULT true,
  CONSTRAINT resultados_evento_pkey PRIMARY KEY (id)
);

-- id_torneo no tiene clave foránea contra torneos en producción, aunque
-- partidos.torneo_id sí la tiene. Inconsistente; reproducido tal cual.
