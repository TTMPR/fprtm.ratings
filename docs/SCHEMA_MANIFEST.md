# Manifiesto del esquema — Kileaaa / FPTM

Inventario objeto por objeto del esquema `public` que la aplicación espera.
Producido en la Fase 1.0 para poder reproducir la base de datos desde cero.

**Estado global: INCOMPLETO.** 5 de 20 tablas no tienen DDL en el
repositorio. Ver "Tablas núcleo" abajo y `sql/schema/010_core_tables.PENDING.sql`.

Leyenda de columnas:

- **DDL** — `repo` (definida en el repositorio) · **`producción`** (hay que
  recuperarla del volcado; no se ha inventado)
- **PII** — contiene datos personales
- **Público** — legible sin sesión con la llave publicable
- **Área** — ratings · inscripción · membresía · copa · admin · sistema
- **Hallazgos** — IDs de `SECURITY_FINDINGS.md`

---

## Tablas núcleo — DDL pendiente de recuperar

| Tabla | Propósito | Fichero origen | DDL | Depende de | PII | Público | Área | Hallazgos |
|---|---|---|---|---|---|---|---|---|
| `"Base de Datos"` | Registro de jugadores y ratings oficiales. PK `"Member ID"`. Columnas confirmadas por las vistas: `First Name`, `Last Name`, `Escuela`, `Rating`, `New Rating`, `Date of Birth`, `Sex`, `Club`, `Expiration Date`; además `Email`, `Home Address`, `photo_url` y columnas `rating_<slug>` por torneo | — | **producción** | — | **Sí** (email, dirección, fecha de nacimiento) | **Sí** | ratings, membresía | **F-01, F-02, F-03, F-05** |
| `torneos` | Torneos. PK `id` | — | **producción** | — | No | Sí | ratings | F-05 |
| `partidos` | Partidos con ratings antes/después. Escrita por `subirApplyRatings()` | — | **producción** | `torneos`, `"Base de Datos"` | No | Sí | ratings | **F-03**, F-05 |
| `resultados_evento` | Resumen por jugador y torneo: `rating_inicio`, `rating_fin`, `ganados`, `perdidos` | — | **producción** | `torneos` | No | Sí | ratings | F-03, F-05 |
| `jugadores` | ⚠ Propósito poco claro. Aparece en el backup y en `trg_audit_jugadores`, pero `index.html` no la consulta en ninguna ruta activa. Posible residuo de una migración anterior | — | **producción** | — | Probable | Desconocido | — | — |

> Las políticas de `SELECT` sobre estas cinco tablas tampoco están en el
> repositorio. La app las lee sin sesión, así que existen en producción.
> Recuperarlas junto al DDL.

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
| `miembros_alertas` | ⚠ Desconocido. `supabase_security_fixes.sql` le hace `ALTER VIEW … security_invoker`, pero **nadie la crea** | — | **producción** | Probablemente `"Base de Datos"` | Probable | Desconocido | — |

---

## Funciones y triggers

| Objeto | Propósito | Fichero origen | DDL | Notas |
|---|---|---|---|---|
| `fn_audit()` | Trigger genérico de auditoría, `SECURITY DEFINER` | `sql/create_audit_log.sql` | repo | Escribe en `audit_log` aunque la API no pueda |
| `trg_audit_*` (7) | Auditoría en `"Base de Datos"`, `jugadores`, `torneos`, `partidos`, `resultados_evento`, `insc_registro`, `membership_requests` | `sql/create_audit_log.sql` | repo | Dependen de las tablas núcleo |
| `fprtm_parse_fecha()` | Convierte los tres formatos históricos de fecha a `DATE` | `sql/create_api_publica.sql` | repo | Replica `_parseDOBStr()` de `index.html` |
| `purge_deleted_torneos()` | Purga la papelera pasados 30 días, `SECURITY DEFINER` | `sql/soft_delete_torneos.sql` | repo | `REVOKE EXECUTE` a `anon`/`authenticated`; job `pg_cron` diario |
| 14 funciones de Copa Olímpica | `inscribir_equipo`, `reservar_cupo_solo`, `liberar_cupo_con_credito`, `nombrar_companero`, `publicar_busca_companero`, `retirar_busca_companero`, `resolver_revision_tecnica`, `insc_*` auxiliares | `sql/create_insc_equipos.sql`, `sql/create_busca_companero.sql` | repo | Lógica de negocio en la base |
| `update_updated_at()` | ⚠ **Nadie la crea.** `supabase_security_fixes.sql` le fija `search_path` | — | **producción** | Probablemente un trigger de `updated_at` |

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

Lo que hay que recuperar de producción antes de poder reproducir el esquema:

1. DDL de `"Base de Datos"`, `torneos`, `partidos`, `resultados_evento`, `jugadores`
2. Políticas de `SELECT` de esas cinco tablas (y el `INSERT` de `resultados_evento`)
3. Vista `miembros_alertas`
4. Función `update_updated_at()` y los triggers que la usen
5. Configuración del bucket `player-photos` y sus políticas
6. Confirmar si `jugadores` sigue teniendo filas o es un residuo

Discrepancias a verificar contra el volcado:

- `membership_requests`, `photo_requests` y `club_change_requests` están
  definidas **dos veces** con formas distintas (`setup_fprtm_database.sql` y
  los `create_*.sql` posteriores). El esquema canónico toma la versión más
  reciente; hay que comprobar cuál coincide con producción.
