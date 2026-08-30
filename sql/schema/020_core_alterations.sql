-- ============================================================================
-- 020 · Columnas e índices añadidos a las tablas núcleo
--
-- Depende de: 010 (las tablas núcleo deben existir).
--
-- Origen (curado, no concatenado):
--   add_categoria_partidos.sql
--   add_fase_ronda_partidos.sql
--   add_publicado_torneos.sql
--   sql/soft_delete_torneos.sql   (sólo la parte de columnas e índices)
--
-- Qué se dejó fuera y por qué:
--   · Los SELECT de verificación al final de cada fichero original: son para
--     mirar con ojos humanos tras aplicar el parche, no forman parte del
--     esquema.
--   · Los UPDATE de relleno (`SET publicado = true WHERE publicado IS NULL`):
--     eran para migrar filas existentes. En una base vacía no hacen nada, y
--     el DEFAULT ya cubre las filas nuevas.
--
-- Todo aquí es idempotente: se puede re-ejecutar sin efectos.
-- ============================================================================


-- ── partidos: categoría ─────────────────────────────────────────────────────
-- Categoría del partido ("1800 Under", "13U Masculino"). Sin ella, publicar
-- un torneo falla: la app agrupa victorias y derrotas por categoría.
ALTER TABLE public.partidos
  ADD COLUMN IF NOT EXISTS categoria TEXT;


-- ── partidos: fase, ronda, grupo, marcador, orden ───────────────────────────
-- Datos que ya vienen en el CSV de Stadium. Sin ellos no se pueden
-- reconstruir las tablas de grupos ni las llaves de un torneo pasado.
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS fase     TEXT;     -- grupos | llave | roundrobin
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS ronda    TEXT;     -- "Final", "Semifinal"…
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS grupo    TEXT;     -- "1", "2"… sólo en grupos
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS marcador TEXT;     -- "9,-6,-6,4,5"
ALTER TABLE public.partidos ADD COLUMN IF NOT EXISTS orden    INTEGER;  -- "Quarterfinal #3" → 3

-- Consultar por torneo + categoría es la operación central de la vista de evento.
CREATE INDEX IF NOT EXISTS idx_partidos_torneo_categoria
  ON public.partidos (torneo_id, categoria);


-- ── Modo borrador: publicado ────────────────────────────────────────────────
-- Un torneo en borrador sólo lo ve el admin. Independiente de los ratings,
-- que se aplican en el paso "Publicar Ratings".
ALTER TABLE public.torneos           ADD COLUMN IF NOT EXISTS publicado BOOLEAN DEFAULT true;
ALTER TABLE public.partidos          ADD COLUMN IF NOT EXISTS publicado BOOLEAN DEFAULT true;
ALTER TABLE public.resultados_evento ADD COLUMN IF NOT EXISTS publicado BOOLEAN DEFAULT true;

-- El público filtra por esta columna en cada consulta.
CREATE INDEX IF NOT EXISTS torneos_publicado_idx           ON public.torneos           (publicado);
CREATE INDEX IF NOT EXISTS partidos_publicado_idx          ON public.partidos          (publicado);
CREATE INDEX IF NOT EXISTS resultados_evento_publicado_idx ON public.resultados_evento (publicado);


-- ── Papelera: deleted_at ────────────────────────────────────────────────────
-- Borrado suave con 30 días de gracia. La purga programada está en 070.
ALTER TABLE public.torneos           ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE public.resultados_evento ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE public.partidos          ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

-- Índice parcial: las consultas de la papelera sólo miran filas borradas.
-- El original crea este índice ÚNICAMENTE sobre torneos. No se añaden los
-- equivalentes en partidos y resultados_evento: no existen en producción y
-- este fichero reproduce producción, no la mejora.
CREATE INDEX IF NOT EXISTS torneos_deleted_at_idx
  ON public.torneos (deleted_at) WHERE deleted_at IS NOT NULL;


-- ── Nota de orden ───────────────────────────────────────────────────────────
-- El parche add_categoria_partidos.sql también añadía
-- resultados_draft.torneo_categoria. Esa línea vive ahora en 040, junto a la
-- creación de resultados_draft: aplicarla aquí falla porque la tabla todavía
-- no existe. Detectado por la validación local en Postgres 16.
