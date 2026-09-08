# Manifiesto del esquema — Kileaaa / FPTM

Inventario objeto por objeto del esquema `public` que la aplicación espera.
Producido en la Fase 1.0 para poder reproducir la base de datos desde cero.

**Estado: completo.** El esquema canónico reconstruye las **22 tablas** y
**7 vistas** que producción reporta, desde una base vacía y sin stubs.
Recuperado en dos extracciones de sólo lectura (2026-09-03 y 2026-09-08).

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

## Miembros e histórico — recuperadas de producción

| Tabla | Propósito | Fichero origen | DDL | Filas en prod. | PII | Público | Hallazgos |
|---|---|---|---|---|---|---|---|
| `miembros` | Registro de miembros de la federación. Alimenta `miembros_alertas`. 17 columnas; `pais` por defecto `'Puerto Rico'`, `status` `'activo'`, `temporada` `2026`. Índices por `nombre_completo` y `status` | `sql/schema/015_miembros_historial.sql` | recuperado | 134 | **Sí, sensible** — correo, teléfono, pueblo, fecha de nacimiento y `responsable`/`relacion`: los datos del adulto responsable de los menores | ver informe privado | ver informe privado |
| `historial_rating` | Histórico de rating por jugador y torneo. FK a `torneos`; índice `(jugador_id, fecha DESC)` | `sql/schema/015_miembros_historial.sql` | recuperado | **0** | No | ver informe privado | ver informe privado |

> **`historial_rating` está vacía en producción.** Tiene estructura, índice y
> clave foránea, pero cero filas: parece preparada para un histórico que
> todavía no se alimenta. El histórico real vive hoy en `resultados_evento` y
> en las columnas `rating_<slug>` de `"Base de Datos"`.
>
> Los conteos de arriba son **observaciones de producción**. El esquema
> canónico crea las tablas vacías; no siembra ninguna fila.

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
| `insc_divisiones` | Divisiones por rating combinado, precio y cupo | `sql/create_insc_equipos.sql` | repo | — | No | Sí | copa | ver informe privado |
| `insc_equipos` | Equipos inscritos, estado de pago y reserva | `sql/create_insc_equipos.sql` | repo | `insc_divisiones`, `"Base de Datos"` | Sí (contacto) | Vía vista | copa | F-04 |
| `insc_busca_companero` | Tablón de jugadores sin pareja | `sql/create_busca_companero.sql` | repo | `"Base de Datos"`, `insc_divisiones` | Sí (contacto) | Vía vista | copa | F-04 |

> ⚠️ **Copa Olímpica 2026 está en curso.** `sql/schema/060_copa_olimpica.sql`
> es una copia literal de `sql/create_insc_equipos.sql` y
> `sql/create_busca_companero.sql` **tal como están en main**. Cualquier
> cambio va primero a esos ficheros; el canónico se resincroniza después,
> nunca al revés.
>
> Resincronizado el 2026-09-08: la copia anterior conservaba el
> comportamiento ya retirado en el que una reserva vencida sin pagar se
> expiraba sola. Hoy no se expira, conserva su cupo, y cancelarla es una
> decisión de la federación. Ver "Deriva detectada" abajo.

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
| `miembros_alertas` | Alertas de vencimiento de membresía de la temporada 2026: `activo` / `por_vencer` / `vencido` y los días restantes. `security_invoker=on`, así que hereda la RLS de `miembros` | `sql/schema/080_views.sql` | **recuperada** | `miembros` (única dependencia, confirmada) | **Sí** — correo, teléfono, pueblo, datos del responsable de menores | ver informe privado | ver informe privado |

> ⚠️ **Rama inalcanzable, reproducida sin corregir.** El `CASE` de la vista
> evalúa `< now() - 11 meses` antes que `< now() - 1 año`. Como toda fila
> vencida hace más de un año cumple también la primera condición, el valor
> `'vencido'` **nunca se devuelve**: una membresía caducada hace dos años se
> reporta como `'por_vencer'`. Corregirlo cambia el comportamiento de
> producción y es una decisión de la federación.

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

**Extraído el 2026-09-08.** La tercera extracción de sólo lectura devolvió la
configuración completa de los dos buckets de Storage y todas las políticas de
`storage.objects`. Con eso, Storage deja de ser un hueco.

Lo extraído **no se publica aquí**. Vive en el paquete privado de staging
(`STAGING_STORAGE.PRIVADO.sql`), junto al snapshot `090` de RLS, por el mismo
motivo: el repositorio es público y entre esas políticas hay una debilidad
todavía abierta. Ver el informe privado de seguridad.

Lo que sí se puede decir en abierto: los dos buckets son públicos y de tipo
estándar, sin versionado, y ninguno tiene límite propio de tamaño ni
restricción de tipo MIME. Producción no tiene ninguna política propia en las
demás tablas del esquema `storage`.

El esquema `storage` en sí —sus tablas, triggers y funciones internas— lo crea
Supabase al provisionar el proyecto. No se reproduce: no es nuestro.

---

## Resumen de huecos

**Cerrado por la extracción de 2026-09-03:** el DDL de las cinco tablas
núcleo, sus políticas RLS completas, la vista `miembros_alertas`, la función
`update_updated_at()` y la confirmación de que `jugadores` tiene 537 filas.

**Cerrado por la segunda extracción (2026-09-08):** el DDL de
`historial_rating` y `miembros`, la definición de `miembros_alertas` con su
`security_invoker=on` y su única dependencia, y la reconciliación completa del
inventario: **22 tablas y 7 vistas, sin diferencias**.

**Cerrado por la tercera extracción (2026-09-08):** el cuerpo de
`rls_auto_enable()`, el event trigger `ensure_rls` que la invoca, el inventario
de event triggers del proyecto y la configuración completa de Storage. Con
esto la paridad de objetos es total: **22 tablas, 7 vistas, 23 funciones y el
event trigger propio, sin diferencias**.

**Todavía pendiente:**

1. Decidir el destino de `jugadores` — 537 filas, lectura pública, ninguna
   ruta de `index.html` la consulta

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


---

## Deriva detectada y corregida — 2026-09-08

Al sincronizar `origin/main` con la rama de migración apareció que el esquema
canónico se había quedado atrás respecto al módulo de Copa Olímpica, que sigue
en uso. Registro de lo encontrado:

### `insc_equipos_liberar(TEXT)` — comportamiento cambiado

| | Copia canónica anterior | main actual |
|---|---|---|
| Reserva vencida sin pagar | `UPDATE … SET estado = 'expirado'` | **no se toca**, conserva su cupo |
| Qué devuelve | `{expirados, promovidos}` | `{promovidos, vencidas_sin_pago}` |
| Quién cancela | el sistema, a las 48 h | **la federación, a mano** |

La función sólo promueve la lista de espera a los cupos realmente libres. El
contador `vencidas_sin_pago` existe para que el panel sepa a quién llamar, no
para actuar.

### `editar_equipo(...)` — función nueva, dependencia viva

Permite a la federación corregir el nombre de un equipo y sus jugadores.
`index.html` la invoca (2 usos) y tiene `GRANT EXECUTE … TO authenticated`.
**Faltaba por completo** en el esquema canónico: un staging construido con la
copia anterior habría roto esa pantalla.

### Scripts de reparación puntual — NO incluidos en el esquema canónico

| Fichero | Qué es | Objetos persistentes | ¿Lo usa la app? | Decisión |
|---|---|---|---|---|
| `sql/restaurar_inscripciones_expiradas.sql` | Devuelve a la vida las reservas que el comportamiento anterior expiró sola. Un solo `UPDATE`, para correr una vez | ninguno | no | **excluido** |
| `sql/deduplicar_inscripciones.sql` | Quita inscripciones duplicadas que aparecieron al restaurar las expiradas | `insc_equipos_deduplicar()` | **no** — `index.html` nunca la llama | **excluido**, ver nota |

`insc_equipos_deduplicar()` sí es una función persistente, pero es una
herramienta de reparación: ninguna ruta de la aplicación la invoca. Se deja
fuera del esquema canónico a propósito. Si algún día el panel la expone, pasa
a ser dependencia y hay que incluirla.

> **Nota de causa raíz.** El commit `4f9ca2c` ("Remove the duplicate
> registrations the restore produced") describe duplicados aparecidos *tras
> una restauración*. Merece la pena comprobar si se relaciona con el defecto
> de clave primaria descrito en el informe privado, que hace que restaurar
> una fila cuyo valor de clave cambió inserte otra en lugar de actualizarla.

### Equivalencia tras la sincronización

| Objeto | Producción | Canónico |
|---|---|---|
| Tablas | 22 | **22** |
| Vistas | 7 | **7** |
| Funciones | 23 | **23** |
| Event triggers propios | 1 | **1** |
| RLS activo | 22 tablas | **22 tablas** |

Sin diferencias. La comparación ya no es de recuentos: la comprueba
`tests/schema-rebuild.test.mjs` contra las **listas de nombres** que devolvió
la extracción, sobre una base reconstruida desde cero. Un recuento correcto
con un nombre distinto pasaría desapercibido; una lista, no.

### `rls_auto_enable` y `ensure_rls`

La última función que faltaba se recuperó en la tercera extracción y está en
`sql/schema/070_functions_triggers.sql`, con el cuerpo literal de
`pg_get_functiondef()`.

Es la función de un event trigger, `ensure_rls`, que al terminar cualquier
`CREATE TABLE`, `CREATE TABLE AS` o `SELECT INTO` sobre `public` activa RLS en
la tabla recién creada. Los fallos se registran en el log y nunca abortan el
DDL. El esquema canónico lo reproduce de forma idempotente, y el test no se
conforma con que exista: crea una tabla de usar y tirar y comprueba que nació
con RLS activo.

Producción tiene otros seis event triggers (`pgrst_ddl_watch`,
`issue_pg_cron_access`, `issue_pg_graphql_access`, `issue_pg_net_access`,
`issue_graphql_placeholder`, `pgrst_drop_watch`). Son de la plataforma
Supabase, propiedad de `supabase_admin`, y **no** se reproducen: los pone
Supabase al crear el proyecto y no forman parte del esquema de la aplicación.

### Un defecto que la reconstrucción destapó

Hasta esta fase, cinco tablas —`Base de Datos`, `jugadores`, `torneos`,
`partidos` y `resultados_evento`— sólo recibían `ENABLE ROW LEVEL SECURITY`
dentro del snapshot `090`, que **no está en el repositorio público**. Quien
reconstruyera el esquema con los ficheros públicos se quedaba con las cinco
tablas más sensibles del sistema sin RLS, es decir sin ninguna restricción.

El fallo no lo vio ninguna revisión a ojo; lo encontró el test de
reconstrucción la primera vez que se ejecutó. Ahora el `ENABLE ROW LEVEL
SECURITY` de esas cinco tablas está en `010_core_tables.sql`, donde se crean.
No define ninguna política ni cambia producción: alinea el fichero con el
estado real y hace que la reconstrucción falle cerrada en vez de abierta.
