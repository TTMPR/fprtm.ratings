# Manifiesto del esquema — Kileaaa / FPTM

Inventario objeto por objeto del esquema `public` que la aplicación espera.
Producido en la Fase 1.0 para poder reproducir la base de datos desde cero.

**Estado: las cinco tablas núcleo ya están recuperadas** (extracción de sólo
lectura de producción, 2026-09-03) y viven en `sql/schema/010_core_tables.sql`.
Quedan **dos tablas nuevas** descubiertas por esa misma extracción cuyo DDL
todavía falta: `historial_rating` y `miembros`.

Leyenda de columnas:

- **DDL** — `repo` (definida en el repositorio) · **`producción`** (hay que
  recuperarla del volcado; no se ha inventado)
- **PII** — contiene datos personales
- **Público** — legible sin sesión con la llave publicable
- **Área** — ratings · inscripción · membresía · copa · admin · sistema
- **Hallazgos** — IDs de `SECURITY_FINDINGS.md`

---

## Tablas núcleo — recuperadas de producción

| Tabla | Propósito | Fichero origen | DDL | Filas | PII | Público | Área | Hallazgos |
|---|---|---|---|---|---|---|---|---|
| `"Base de Datos"` | Registro de jugadores y ratings oficiales. 16 columnas. **PK compuesta de 10 columnas**, todas `NOT NULL` — `Member ID` NO es único. Sin columna `photo_url` | `sql/schema/010_core_tables.sql` | recuperado | 619 | **Sí** (email, dirección, fecha nac.) | **Sí** | ratings, membresía | ver informe privado |
| `torneos` | Torneos. Columnas no documentadas antes: `lugar`, `tipo`, `temporada` (def. 2026), `notas` | `sql/schema/010_core_tables.sql` | recuperado | 6 | No | Sí | ratings | F-05 |
| `partidos` | Partidos con ratings antes/después. **Pares de columnas duplicadas**: `categoria_evento`/`categoria`, `score`/`marcador`; además `puntos_a`/`puntos_b` sin uso. FK real a `torneos` | `sql/schema/010_core_tables.sql` | recuperado | 1 829 | No | Sí | ratings | F-03, F-05 |
| `resultados_evento` | Resumen por jugador y torneo. `id` es `IDENTITY ALWAYS`, no serial. Sin FK a `torneos` (inconsistente con `partidos`) | `sql/schema/010_core_tables.sql` | recuperado | 780 | No | Sí | ratings | F-03 |
| `jugadores` | **Segundo registro de jugadores**, distinto de `Base de Datos`. UUID, `rating_actual` (def. 1000), campos de la temporada 2025. Lectura pública, trigger de auditoría, y **no** se consulta desde `index.html` | `sql/schema/010_core_tables.sql` | recuperado | 537 | Probable | **Sí** | — | — |

> **`jugadores` no es un residuo vacío.** Tiene 537 filas — exactamente el
> número de jugadores de `restore_rating_backup.sql`, lo que sugiere que fue
> el origen de aquel snapshot. Sigue pendiente decidir si va a staging, se
> congela o se retira.

---

## Tablas descubiertas — DDL todavía pendiente

| Tabla | Qué se sabe | DDL | En el backup | Hallazgos |
|---|---|---|---|---|
| `historial_rating` | Histórico de ratings, a juzgar por el nombre. Secuencia propia `historial_rating_id_seq` | **producción** | Añadida en Fase 1.0G | ver informe privado |
| `miembros` | Registro de miembros de la federación. Alimenta la vista `miembros_alertas`. **Contiene datos personales sensibles**, incluidos los del adulto responsable de los jugadores menores | **producción** | Añadida en Fase 1.0G | ver informe privado |

Hace falta una segunda extracción de sólo lectura para su DDL antes de dar el
esquema por completo.

---

## Inscripciones

| Tabla | Propósito | Fichero origen | DDL | Depende de | PII | Público | Área | Hallazgos |
|---|---|---|---|---|---|---|---|---|
| `insc_registro` | Inscripciones a torneo: categorías (JSONB), base, total, pagado, `monto_pagado`, `referencia`, `dob`, `sex`, `club` | `create_insc_registro.sql` + 5 `add_*.sql` | repo | `"Base de Datos"` (por convención, sin FK) | **Sí** (`dob`, nombre) | **Sí** (`public_select_insc_registro`) | inscripción | F-04 |
| `resultados_draft` | Borrador de resultados antes de publicar ratings | `create_resultados_draft.sql` + `add_categoria_partidos.sql` | repo | `torneos` | No | No | ratings | F-04 |

---

## Membresía, fotos y solicitudes

| Tabla | Propósito | Fichero origen | DDL | Depende de | PII | Público | Área | Hallazgos |
|---|---|---|---|---|---|---|---|---|
| `membership_requests` | Solicitudes de membresía nueva | `setup_fprtm_database.sql`, `create_membership_requests.sql` | repo ⚠ **definida dos veces** | `"Base de Datos"` | **Sí** | Inserción pública | membresía | F-05 |
| `photo_requests` | Fotos de jugador pendientes de aprobar | `create_photo_requests.sql`, `add_is_minor_to_photo_requests.sql` | repo ⚠ también en `setup_fprtm_database.sql` | `"Base de Datos"` | **Sí** (`is_minor`: menores) | Inserción pública | membresía | F-05 |
| `club_change_requests` | Solicitudes de cambio de club | `club_change_requests.sql` | repo ⚠ también en `setup_fprtm_database.sql` | `"Base de Datos"`, `clubs` | Sí | Sí | admin | F-05 |
| `player_reg_tokens` | Tokens de alta de jugador | `create_player_reg_tokens.sql` | repo | — | **Credenciales** | No | admin | F-04 |
| `player_reg_submissions` | Formularios de alta enviados | `create_player_reg_submissions.sql` | repo | `player_reg_tokens(token)` — **la única FK declarada del repo** | **Sí** (formulario completo) | Inserción pública | admin | F-04 |

---

## Configuración, contenido y clubes

| Tabla | Propósito | Fichero origen | DDL | Depende de | PII | Público | Área | Hallazgos |
|---|---|---|---|---|---|---|---|---|
| `app_settings` | Interruptores: `inscripciones_open`, `torneo_archivado`, `insc_ignorar_deadline`, `insc_parte_abierta`, `insc_equipos_reserva_horas` | `create_app_settings.sql`, `fix_app_settings_enable_rls.sql` | repo | — | No | **Sí** (lectura) | sistema | **F-08**, F-04 |
| `clubs` | Clubes: logo, descripción, contacto | `create_clubs_table.sql`, `create_club_info_requests.sql` | repo | — | Contacto del club | Sí | admin | F-04 |
| `club_info_requests` | Solicitudes de actualización de info de club | `create_club_info_requests.sql` | repo | `clubs` | Contacto | Sí | admin | F-04 |
| `articulos` | Noticias | `create_articulos.sql` | repo | — | No | Sí (publicadas) | sistema | F-04 |

---

## Copa Olímpica

| Tabla | Propósito | Fichero origen | DDL | Depende de | PII | Público | Área | Hallazgos |
|---|---|---|---|---|---|---|---|---|
| `insc_divisiones` | Divisiones por rating combinado, precio y cupo | `sql/create_insc_equipos.sql` | repo | — | No | Sí | copa | F-04 |
| `insc_equipos` | Equipos inscritos, estado de pago y reserva | `sql/create_insc_equipos.sql` | repo | `insc_divisiones`, `"Base de Datos"` | Sí (contacto) | Vía vista | copa | F-04 |
| `insc_busca_companero` | Tablón de jugadores sin pareja | `sql/create_busca_companero.sql` | repo | `"Base de Datos"`, `insc_divisiones` | Sí (contacto) | Vía vista | copa | F-04 |

> ⚠️ **Las tres están fuera del backup semanal.** No aparecen en la lista
> `TABLES` de `backup/export_backup.mjs`. Es el módulo con dinero asociado
> más reciente. Corrección propuesta en la Fase 1.0G.

---

## Sistema

| Tabla | Propósito | Fichero origen | DDL | Depende de | PII | Público | Área | Hallazgos |
|---|---|---|---|---|---|---|---|---|
| `audit_log` | Caja negra de cambios (append-only, escribe sólo el trigger) | `sql/create_audit_log.sql` | repo | Las tablas auditadas | **Sí** — `old_data`/`new_data` guardan filas completas | No | sistema | **F-06** |

---

## Vistas

| Vista | Propósito | Fichero origen | DDL | Depende de | PII | Público | Hallazgos |
|---|---|---|---|---|---|---|---|
| `api_jugadores` | Atletas, ratings y estado de membresía para la web oficial | `sql/create_api_publica.sql` | repo | `"Base de Datos"` | **No** — creada precisamente para excluirla | **Sí** | mitiga F-02 |
| `api_clubes` | Clubes con logo e info de contacto | `sql/create_api_publica.sql` | repo | `clubs` | No | **Sí** | — |
| `api_torneos` | Torneos publicados | `sql/create_api_publica.sql` | repo | `torneos` | No | **Sí** | — |
| `insc_equipos_publico` | Equipos sin datos de contacto | `sql/create_insc_equipos.sql` | repo | `insc_equipos` | No | **Sí** | — |
| `insc_equipos_cupos` | Cupos libres por división | `sql/create_insc_equipos.sql` | repo | `insc_equipos`, `insc_divisiones` | No | **Sí** | — |
| `insc_busca_companero_publico` | Tablón sin datos de contacto | `sql/create_busca_companero.sql` | repo | `insc_busca_companero` | No | **Sí** | — |
| `miembros_alertas` | Alertas de vencimiento de membresía para la temporada 2026: calcula `activo` / `por_vencer` / `vencido` y los días restantes. `security_invoker=on` | — | **recuperada** (definición completa en la extracción) | `miembros` | **Sí** — email, teléfono, dirección, datos del responsable de menores | ver informe privado | ver informe privado |

---

## Funciones y triggers

| Objeto | Propósito | Fichero origen | DDL | Notas |
|---|---|---|---|---|
| `fn_audit()` | Trigger genérico de auditoría, `SECURITY DEFINER` | `sql/create_audit_log.sql` | repo | Escribe en `audit_log` aunque la API no pueda |
| `trg_audit_*` (7) | Auditoría en `"Base de Datos"`, `jugadores`, `torneos`, `partidos`, `resultados_evento`, `insc_registro`, `membership_requests` | `sql/create_audit_log.sql` | repo | Dependen de las tablas núcleo |
| `fprtm_parse_fecha()` | Convierte los tres formatos históricos de fecha a `DATE` | `sql/create_api_publica.sql` | repo | Replica `_parseDOBStr()` de `index.html` |
| `purge_deleted_torneos()` | Purga la papelera pasados 30 días, `SECURITY DEFINER` | `sql/soft_delete_torneos.sql` | repo | `REVOKE EXECUTE` a `anon`/`authenticated`; job `pg_cron` diario |
| 14 funciones de Copa Olímpica | `inscribir_equipo`, `reservar_cupo_solo`, `liberar_cupo_con_credito`, `nombrar_companero`, `publicar_busca_companero`, `retirar_busca_companero`, `resolver_revision_tecnica`, `insc_*` auxiliares | `sql/create_insc_equipos.sql`, `sql/create_busca_companero.sql` | repo | Lógica de negocio en la base |
| `update_updated_at()` | Trigger de `updated_at`: `NEW.updated_at = NOW()`. `search_path` fijado a `''` | — | **recuperada** | No hay ningún trigger que la use en las tablas núcleo |

---

## Extensiones

| Extensión | Para qué | Origen |
|---|---|---|
| `pg_cron` | Job diario de purga de la papelera (3:30 UTC) | `sql/soft_delete_torneos.sql` |

---

## Buckets de Storage

| Bucket | Público | Para qué | DDL |
|---|---|---|---|
| `club-logos` | Sí | Logos de club | repo (`create_clubs_table.sql`) |
| `player-photos` | Sí | Fotos de jugador — **incluidos menores** | **producción** ⚠ ningún fichero lo crea |
| `backups` | **No** | Destino del backup semanal | Lo crea `backup/export_backup.mjs` |

---

## Resumen de huecos

**Cerrado por la extracción de 2026-09-03:** el DDL de las cinco tablas
núcleo, sus políticas RLS completas, la vista `miembros_alertas`, la función
`update_updated_at()` y la confirmación de que `jugadores` tiene 537 filas.

**Todavía pendiente:**

1. DDL de `historial_rating` y `miembros` (segunda extracción)
2. Políticas del bucket `player-photos` (el bucket existe y es público;
   sus políticas de `storage.objects` no se extrajeron)
3. Decidir el destino de `jugadores`

Discrepancias a verificar contra el volcado:

- `membership_requests`, `photo_requests` y `club_change_requests` están
  definidas **dos veces** con formas distintas (`setup_fprtm_database.sql` y
  los `create_*.sql` posteriores). El esquema canónico toma la versión más
  reciente; hay que comprobar cuál coincide con producción.


---

## Nota sobre la revisión de seguridad

Este repositorio es **público**. El análisis de las políticas RLS de producción
—incluidos los hallazgos abiertos que todavía no se han corregido— se mantiene
**fuera de Git** a propósito, para no publicar detalles explotables de un
sistema en producción antes de arreglarlo.

Las columnas de hallazgos de este documento dicen "ver informe privado" donde
correspondería un identificador. Pide el informe a quien lleve la migración.
