-- ============================================================================
-- 015 · miembros e historial_rating — RECUPERADAS DE PRODUCCIÓN
--
-- Origen: segunda extracción de sólo lectura del catálogo de producción
-- (2026-09-08, PostgreSQL 17.6). Nada inventado: cada tipo, default,
-- restricción e índice viene del volcado.
--
-- Depende de: 010 (historial_rating tiene una clave foránea a torneos).
--
-- Estas dos tablas no aparecían en NINGÚN fichero del repositorio ni en el
-- backup semanal. Las destapó la primera extracción al listar el inventario
-- completo de `public`. Con ellas, el esquema canónico cubre las 22 tablas
-- que producción reporta.
--
-- Observación de producción, NO se siembran datos aquí:
--   historial_rating   0 filas
--   miembros         134 filas
--
-- Las políticas RLS de estas tablas NO están en este fichero. Van en el
-- snapshot 090, que se mantiene fuera del repositorio público mientras haya
-- hallazgos de seguridad abiertos. Aquí sólo se activa RLS, que sin políticas
-- deniega todo — el valor por defecto seguro.
-- ============================================================================


-- ============================================================================
-- miembros — registro de miembros de la federación
-- ============================================================================
--
-- ⚠️  DATOS PERSONALES SENSIBLES. Además de correo, teléfono, dirección
--     (pueblo/pais) y fecha de nacimiento, guarda `responsable` y `relacion`:
--     los datos del adulto responsable de los jugadores menores de edad.
--     Cualquier copia a un entorno de pruebas debe anonimizarse
--     (ver docs/PHASE0_BACKUP_AND_STAGING.md, Parte 3).
--
-- bigserial reproduce exactamente el default de producción
-- (nextval('miembros_id_seq')) y deja la secuencia como propietaria de id.

CREATE TABLE IF NOT EXISTS public.miembros (
  id               bigserial   NOT NULL,
  nombre_completo  text        NOT NULL,
  email            text,
  telefono         text,
  club             text,
  sexo             text,
  edad             integer,
  fecha_nac        date,
  fecha_membresia  timestamptz,
  ath_id           text,
  pueblo           text,
  pais             text        DEFAULT 'Puerto Rico'::text,
  responsable      text,
  relacion         text,
  status           text        DEFAULT 'activo'::text,
  temporada        integer     DEFAULT 2026,
  created_at       timestamptz DEFAULT now(),
  CONSTRAINT miembros_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_miembros_nombre ON public.miembros USING btree (nombre_completo);
CREATE INDEX IF NOT EXISTS idx_miembros_status ON public.miembros USING btree (status);

ALTER TABLE public.miembros ENABLE ROW LEVEL SECURITY;

-- Sin triggers en producción. `edad` es una columna suelta, no derivada de
-- `fecha_nac`: nada la mantiene sincronizada.


-- ============================================================================
-- historial_rating — histórico de rating por jugador y torneo
-- ============================================================================
--
-- Vacía en producción (0 filas) pero con estructura completa, índice y clave
-- foránea. Parece preparada para un histórico que todavía no se alimenta: el
-- histórico real vive hoy en `resultados_evento` y en las columnas
-- `rating_<slug>` de "Base de Datos".
--
-- `jugador_id` es bigint sin clave foránea. No podría tenerla contra
-- "Base de Datos", cuya PK compuesta no deja que "Member ID" sea único.

CREATE TABLE IF NOT EXISTS public.historial_rating (
  id          bigserial   NOT NULL,
  jugador_id  bigint,
  torneo_id   bigint,
  rating      integer     NOT NULL,
  fecha       date        NOT NULL,
  created_at  timestamptz DEFAULT now(),
  CONSTRAINT historial_rating_pkey PRIMARY KEY (id),
  CONSTRAINT historial_rating_torneo_id_fkey FOREIGN KEY (torneo_id)
    REFERENCES public.torneos(id)
);

CREATE INDEX IF NOT EXISTS idx_historial_jugador
  ON public.historial_rating USING btree (jugador_id, fecha DESC);

ALTER TABLE public.historial_rating ENABLE ROW LEVEL SECURITY;
