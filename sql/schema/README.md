# Esquema canónico — Kileaaa / FPTM

Representación versionada del esquema `public` que la aplicación espera.
Existe para poder levantar un entorno **desde cero** — en concreto el staging
de la Fase 1.0 — sin depender de que alguien recuerde el orden correcto de
los ~30 ficheros `.sql` sueltos de la raíz del repositorio.

> **Estado: completo.** Reconstruye las **22 tablas** y **7 vistas** que
> producción reporta, desde una base vacía y sin stubs. Verificado contra
> PostgreSQL 16 el 2026-09-08.

## Orden de aplicación

El número **es** el orden. Aplícalos de menor a mayor.

| Fichero | Contenido |
|---|---|
| `000_extensions.sql` | `pg_cron` |
| `010_core_tables.sql` | Tablas núcleo, recuperadas de producción |
| `015_miembros_historial.sql` | `miembros` e `historial_rating`, recuperadas de producción |
| `020_core_alterations.sql` | Columnas e índices añadidos a las tablas núcleo |
| `030_registration.sql` | `insc_registro` y sus parches |
| `040_content.sql` | `app_settings`, `articulos`, `clubs`, `club_info_requests` |
| `050_membership.sql` | Membresías, fotos, cambios de club, registro de jugadores, `resultados_draft` |
| `060_copa_olimpica.sql` | Equipos, divisiones y Busco Compañero |
| `070_functions_triggers.sql` | `audit_log` + `fn_audit` + triggers, purga de la papelera |
| `080_views.sql` | `fprtm_parse_fecha` y las vistas `api_*` |
| `090_rls_current_snapshot.sql` | RLS — **no está en este repositorio**, ver abajo |
| `100_storage.sql` | Buckets y políticas de Storage — **sólo Supabase** |

## Reconciliación con producción

| | Producción | Canónico |
|---|---|---|
| Tablas | 22 | **22** |
| Vistas | 7 | **7** |

Sin diferencias. La comparación se hace contra el inventario completo de
`public` que devuelve la extracción de sólo lectura, no contra una lista
escrita a mano.

Dependencias no obvias que la validación local destapó:

- `040` va antes que `050`: `club_info_requests` hace `ALTER TABLE clubs`.
- `resultados_draft.torneo_categoria` vive en `050`, no en `020`, aunque el
  parche original la añadía junto a `partidos.categoria`.
- `015` va después de `010`: `historial_rating` tiene una clave foránea a
  `torneos`.
- `080` define `fprtm_parse_fecha` antes de las vistas que la usan, y
  `miembros_alertas` depende de `miembros` (creada en `015`).

## Seguridad: el fichero 090 no está aquí

Este repositorio es **público**. El snapshot de las políticas RLS de
producción se mantiene **fuera de Git** mientras haya hallazgos de seguridad
abiertos sin corregir: publicar la configuración exacta de un sistema en uso
antes de arreglarlo es un riesgo innecesario.

Los ficheros de este directorio **activan RLS** en cada tabla (que sin
políticas deniega todo — el valor por defecto seguro) pero no definen las
políticas de las tablas núcleo. Para levantar un staging equivalente a
producción hace falta también el `090`, que se entrega por canal privado.

Cuando esté aplicado, `090` reproduce producción **incluidas sus debilidades**.
Es deliberado: staging tiene que empezar pareciéndose a producción o deja de
servir para validar nada. El endurecimiento es Fase 1.2/1.3 y se prueba allí
antes de tocar producción.

**No corrijas seguridad en estos ficheros sin aprobación explícita.**

## Cómo se construyó

Curado, no concatenado. De cada fichero original se tomó el DDL y se
descartó lo que no es esquema:

- Los `SELECT` de verificación del final de cada parche.
- Los `UPDATE` de relleno que migraban filas existentes (en una base vacía
  no hacen nada; el `DEFAULT` cubre las filas nuevas).
- Las cargas de datos históricos (`carga_*.sql`) y los scripts destructivos
  (`borrar_*.sql`, `restore_rating_backup.sql`), que no son esquema.

Se añadió `DROP POLICY IF EXISTS` antes de cada `CREATE POLICY` que no lo
tenía, para que los ficheros sean re-ejecutables. El estado final de las
políticas es idéntico.

Los ficheros originales **siguen en el repositorio y no se han tocado**. Este
directorio es una vista derivada, no un reemplazo.

## Validación

Reconstrucción desde una base vacía contra PostgreSQL 16 local (nunca contra
producción), en orden numérico estricto y **sin stubs**:

```
✓ 010_core_tables.sql        ✓ 015_miembros_historial.sql
✓ 020_core_alterations.sql   ✓ 030_registration.sql
✓ 040_content.sql            ✓ 050_membership.sql
✓ 060_copa_olimpica.sql      ✓ 070_functions_triggers.sql  (sin pg_cron)
✓ 080_views.sql              ✓ 090 (privado)
```

Resultado: **22 tablas, 7 vistas**, 57 políticas, RLS activo en las 22 tablas.
Todos los ficheros son idempotentes: la segunda pasada sobre la misma base no
falla.

Una salvedad: `pg_cron` no está instalado en el Postgres de prueba, así que el
job de purga de `070` no se validó. En Supabase se habilita desde
Database → Extensions.

La validación de verdad —en Supabase, con el `090` aplicado— queda pendiente
hasta que exista staging.
