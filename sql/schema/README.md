# Esquema canónico — Kileaaa / FPTM

Representación versionada del esquema `public` que la aplicación espera.
Existe para poder levantar un entorno **desde cero** — en concreto el staging
de la Fase 1.0 — sin depender de que alguien recuerde el orden correcto de
los ~30 ficheros `.sql` sueltos de la raíz del repositorio.

> **Estado: INCOMPLETO.** Faltan las cinco tablas núcleo. Ver
> `010_core_tables.PENDING.sql` y la sección "Qué falta".

## Orden de aplicación

El número **es** el orden. Aplícalos de menor a mayor.

| Fichero | Contenido |
|---|---|
| `000_extensions.sql` | `pg_cron` |
| `010_core_tables.PENDING.sql` | ⛔ **Tablas núcleo — DDL pendiente de recuperar** |
| `020_core_alterations.sql` | Columnas e índices añadidos a las tablas núcleo |
| `030_registration.sql` | `insc_registro` y sus parches |
| `040_content.sql` | `app_settings`, `articulos`, `clubs`, `club_info_requests` |
| `050_membership.sql` | Membresías, fotos, cambios de club, registro de jugadores, `resultados_draft` |
| `060_copa_olimpica.sql` | Equipos, divisiones y Busco Compañero |
| `070_functions_triggers.sql` | `audit_log` + `fn_audit` + triggers, purga de la papelera |
| `080_views.sql` | `fprtm_parse_fecha` y las vistas `api_*` |
| `090_rls_current_snapshot.sql` | RLS de las tablas núcleo — **foto de producción, debilidades incluidas** |
| `100_storage.sql` | Buckets y políticas de Storage — **sólo Supabase** |

Dependencias no obvias que la validación local destapó:

- `040` va antes que `050`: `club_info_requests` hace `ALTER TABLE clubs`.
- `resultados_draft.torneo_categoria` vive en `050`, no en `020`, aunque el
  parche original la añadía junto a `partidos.categoria`.
- `080` define `fprtm_parse_fecha` antes de las vistas que la usan.

## Qué falta

`010_core_tables.PENDING.sql` **no contiene DDL**. Cinco tablas que la
aplicación usa a diario no tienen `CREATE TABLE` en ningún sitio del
repositorio: `"Base de Datos"`, `torneos`, `partidos`, `resultados_evento` y
`jugadores`. Existen sólo en el proyecto Supabase de producción.

Su definición **no se ha inventado**. Un staging con tipos y restricciones
adivinados se parecería a producción sin serlo, y los tests pasarían contra
un esquema que no es el real — peor que no tener staging.

El fichero lleva una guarda `RAISE EXCEPTION` para que nadie aplique el
esquema a medias por descuido.

Para recuperarlo: `docs/STAGING_RUNBOOK.md`, sección "Extracción del esquema".
El inventario completo, objeto por objeto, está en `docs/SCHEMA_MANIFEST.md`.

## Seguridad: esto reproduce producción, no la arregla

`090_rls_current_snapshot.sql` reproduce las políticas actuales **incluidas
sus debilidades** (F-02, F-05 en `SECURITY_FINDINGS.md`). Es deliberado:
staging tiene que empezar pareciéndose a producción, o deja de servir para
validar nada. El endurecimiento es Fase 1.2/1.3 y se prueba en staging antes
de tocar producción.

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

Probado contra PostgreSQL 16 local (no contra producción):

```
✓ 020_core_alterations.sql
✓ 030_registration.sql
✓ 040_content.sql
✓ 050_membership.sql
✓ 060_copa_olimpica.sql
✓ 070_functions_triggers.sql    (sin el bloque pg_cron)
✓ 080_views.sql
✓ 090_rls_current_snapshot.sql
```

Resultado: 20 tablas, 6 vistas, 20 funciones, 44 políticas, 9 triggers.
Todos los ficheros son idempotentes: la segunda pasada sobre la misma base
no falla.

Dos salvedades:

1. La validación usó un **stub desechable** para las cinco tablas núcleo,
   creado en `/tmp` y nunca en el repositorio. Demuestra que el resto del
   esquema encaja, **no** que el esquema esté completo.
2. `pg_cron` no está instalado en el Postgres de prueba, así que el job de
   purga de `070` no se validó. En Supabase se habilita desde
   Database → Extensions.

La validación de verdad —esquema real, en Supabase— queda pendiente hasta
que exista staging.
