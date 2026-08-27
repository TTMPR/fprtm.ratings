# Fase 0 · Backup, restauración y arquitectura de staging

Levantamiento del sistema de respaldo actual y pasos exactos para crear un
proyecto Supabase de staging.

**No se ha creado ningún proyecto. No se ha ejecutado ninguna migración.
No se ha tocado producción.** Este documento es la propuesta previa a la
aprobación.

---

## Parte 1 — El sistema de backup actual

### Qué se respalda

`backup/export_backup.mjs` exporta 17 tablas, cada una en `.json` (fidelidad
completa, es la que usa la restauración) y `.csv` (lectura humana):

| | Tablas |
|---|---|
| Registro y ratings | `Base de Datos`, `jugadores`, `torneos`, `partidos`, `resultados_evento` |
| Inscripciones | `insc_registro`, `player_reg_submissions`, `player_reg_tokens` |
| Federación | `membership_requests`, `photo_requests`, `club_change_requests`, `club_info_requests`, `clubs` |
| Contenido y sistema | `articulos`, `app_settings`, `resultados_draft`, `audit_log` |

Las tablas que no existen en el proyecto se saltan con un aviso, y el export
sigue. Cada carpeta lleva un `_resumen.txt` con el conteo por tabla.

### Cada cuánto

`.github/workflows/weekly-backup.yml` — cron `0 7 * * 1`: **lunes 07:00 UTC**
(03:00 en Puerto Rico). También se puede lanzar a mano con `workflow_dispatch`.

### Dónde se guarda

Bucket **privado** `backups` del **mismo** proyecto Supabase
(`qrvyfdpwtearfpjruwja`), en carpetas por fecha: `backups/YYYY-MM-DD/tabla.json`.

La decisión de no subirlo a GitHub está razonada en el propio workflow y es
correcta: el repositorio es público y los exports contienen correos, fechas
de nacimiento y direcciones — en un repositorio público los artifacts de
Actions son descargables por cualquiera.

### Cómo funciona la restauración

`backup/restore_backup.mjs` lee una carpeta de backup y hace `upsert` contra
un proyecto **destino** vía PostgREST:

```bash
TARGET_SUPABASE_URL=https://<proyecto>.supabase.co \
TARGET_SERVICE_ROLE_KEY=eyJ... \
node backup/restore_backup.mjs ./backup-out/2026-07-11
```

Detalles que importan:
- Es idempotente: hace `on_conflict` por clave primaria y fusiona duplicados,
  así que se puede re-ejecutar sin duplicar filas.
- `Base de Datos` usa `Member ID` como PK; `app_settings` usa `key`; el resto `id`.
- `audit_log` se restaura sin la columna `id` (es `GENERATED ALWAYS`).
- **Requiere que el destino ya tenga el esquema.** El script sólo mueve datos.

### Qué NO cubre

| Hueco | Consecuencia |
|---|---|
| **Supabase Storage** (`club-logos`, `player-photos`) | Los ficheros de imagen no se respaldan. Sólo van las URL que estén en las tablas. Una pérdida del proyecto se lleva las fotos. |
| **Usuarios de Supabase Auth** | Las cuentas (`auth.users`) no se exportan. Una restauración deja los datos pero no quién puede entrar. |
| **Esquema** | No hay volcado de DDL. El esquema se reconstruye ejecutando a mano los `setup_*.sql` / `create_*.sql`, que no están ordenados ni versionados. |
| **Políticas RLS, funciones, triggers** | Van dentro de esos mismos ficheros SQL, con el mismo problema de orden. |
| **Tabla `insc_equipos` / `insc_divisiones` / `insc_busca_companero`** | Creadas en `sql/create_insc_equipos.sql` y `sql/create_busca_companero.sql`, **no** están en la lista `TABLES` del exportador. El módulo Copa Olímpica queda fuera del backup. |
| **Retención** | Nada borra carpetas viejas, y nada verifica que el backup de esta semana se haya hecho. Un fallo silencioso del workflow no avisa. |

### Riesgos y supuestos

1. **Punto único de fallo** (F-07 en `SECURITY_FINDINGS.md`). Datos y copias
   viven en el mismo proyecto. Un borrado, una suspensión de cuenta o una
   `service_role` comprometida se lo lleva todo.
2. **El ejercicio de restauración no consta como realizado.** El README lo
   describe con precisión y avisa: *"Backup que nunca se ha restaurado =
   esperanza, no backup."* No hay rastro de que se haya hecho.
3. **La reconstrucción del esquema es manual y frágil.** Hay ~30 ficheros
   `.sql` en la raíz sin orden explícito, mezclados con cargas de datos
   históricas (`carga_*.sql`) y scripts destructivos (`borrar_torneo.sql`).
   Nadie sabe hoy cuál es la secuencia correcta para levantar un proyecto
   desde cero — y eso es exactamente lo que hace falta para el staging.
4. **Sin monitorización.** El workflow pone `exitCode = 1` si falla una tabla,
   pero nadie recibe aviso.
5. **`insc_equipos` fuera del backup** significa que el módulo con dinero
   asociado más reciente no está protegido.

---

## Parte 2 — Staging: la forma más segura

### Principio rector

**Producción y staging nunca comparten datos escribibles.** Eso implica, sin
excepciones:

- Proyectos Supabase **distintos**, con URL, claves y base de datos propias.
- El flujo es **de una sola dirección**: producción → staging. Nunca al revés.
- Ninguna credencial de producción se configura jamás en staging, ni al
  contrario. No se comparten buckets, ni funciones, ni webhooks.
- Staging **no** envía correos reales, no cobra, y no llama a ATH Móvil ni
  Stripe en modo producción.

### Configuración propuesta

| | Producción | Staging |
|---|---|---|
| Proyecto Supabase | `qrvyfdpwtearfpjruwja` | nuevo, p. ej. `kileaaa-staging` |
| Región | la actual | la misma, para que los tiempos se parezcan |
| Plan | el actual | Free es suficiente para Fase 0-2 |
| Datos | reales | copia anonimizada (ver Parte 3) |
| Auth | cuentas reales | cuentas de prueba propias |
| Storage | `club-logos`, `player-photos`, `backups` | buckets vacíos |
| Acceso | quien corresponda | mismo equipo, credenciales distintas |

### Pasos exactos (para ejecutar tras aprobación)

**1. Crear el proyecto**
En el panel de Supabase: *New project* → nombre `kileaaa-staging`, misma
región que producción, contraseña de base de datos nueva y distinta.
Guardar `SUPABASE_URL`, la clave publicable y la `service_role` del proyecto
nuevo por separado de las de producción.

**2. Fijar el orden del esquema**
Antes de nada hay que resolver el riesgo 3. Propuesta de secuencia, a
verificar ejecutándola en staging:

```
1. setup_fprtm_database.sql          membership_requests, photo_requests,
                                     club_change_requests + RLS base
2. create_clubs_table.sql            clubs + buckets de logos
3. create_insc_registro.sql          inscripciones
4. create_app_settings.sql           interruptores
5. create_articulos.sql              noticias
6. create_photo_requests.sql         (si no lo cubre el paso 1)
7. create_club_info_requests.sql
8. create_player_reg_tokens.sql
9. create_player_reg_submissions.sql
10. create_resultados_draft.sql
11. create_membership_requests.sql   (si no lo cubre el paso 1)
12. sql/create_audit_log.sql         auditoría
13. sql/soft_delete_torneos.sql      papelera
14. sql/create_insc_equipos.sql      Copa Olímpica
15. sql/create_busca_companero.sql
16. sql/create_api_publica.sql       vistas públicas
17. add_*.sql                        columnas añadidas después
```

Las tablas `Base de Datos`, `torneos`, `partidos` y `resultados_evento` no
tienen fichero de creación en el repositorio — existen sólo en producción.
**Hay que extraer su DDL** (Supabase → Database → Schema, o
`pg_dump --schema-only`) y guardarla como `sql/schema_core.sql` antes de
poder levantar staging. Es el primer trabajo real de esta parte.

**3. Cargar datos**
Con la copia anonimizada de la Parte 3:
```bash
TARGET_SUPABASE_URL=https://<staging>.supabase.co \
TARGET_SERVICE_ROLE_KEY=<service_role de staging> \
node backup/restore_backup.mjs ./backup-anonimizado/YYYY-MM-DD
```

**4. Verificar**
Comparar conteos por tabla contra el `_resumen.txt`, y abrir dos o tres
jugadores al azar. Esto **cierra a la vez el ejercicio de restauración
pendiente** del riesgo 2: si la carga funciona, los backups quedan
verificados por primera vez.

**5. Apuntar la aplicación**
Sin Developer Mode todavía, la forma más simple y segura es una copia local
de `index.html` con la URL y la clave de staging. Cuando llegue el Developer
Mode (Fase 1), el cambio de entorno pasa a ser una capacidad del propio modo.

### Salvaguardas

- Nombre del proyecto claramente distinto para no confundirlos en el panel.
- Un banner permanente de color en cualquier build que apunte a staging.
- La `service_role` de staging **no** se guarda como secreto de GitHub junto
  a la de producción; conviene otro nombre (`STAGING_SERVICE_ROLE_KEY`) para
  que no pueda usarse por error en el workflow de backup.
- Regla escrita: ningún script apunta a las dos a la vez. `restore_backup.mjs`
  ya ayuda, porque sólo acepta `TARGET_*` y nunca escribe en el origen.

---

## Parte 3 — Qué copiar y qué anonimizar

Staging debe parecerse a producción en **forma y volumen**, no en identidad.
Los cálculos de rating no dependen de ningún dato personal: `getPoints()`
sólo usa números, y el nombre y el club viajan a `resultados_evento` sin
intervenir en el cálculo. Se puede anonimizar sin perder fidelidad.

### Copiar tal cual

| Tabla | Motivo |
|---|---|
| `torneos`, `partidos`, `resultados_evento` | Ratings e historial: el material de los tests de caracterización. No contienen datos personales. |
| `Base de Datos` → `Member ID`, `Rating`, `New Rating`, `Sex`, `Club` | Necesarios para reproducir el comportamiento. No identifican por sí solos. |
| `app_settings`, `clubs`, `articulos` | Configuración y contenido público. |
| `resultados_draft` | Ejercita el flujo de borrador. |

### Anonimizar

| Campo | Tratamiento propuesto |
|---|---|
| `Base de Datos."Name"` | Sustituir por `Jugador <Member ID>`. Conserva unicidad y longitud. |
| `Base de Datos."Email"` | `jugador+<id>@staging.invalid` — el TLD `.invalid` está reservado y no puede entregar correo. |
| `Base de Datos."Home Address"` | Vaciar. No hay ninguna funcionalidad que lo necesite. |
| `Base de Datos."Date of Birth"` | **Conservar sólo el año, con día y mes fijos** (`AAAA-01-01`). Las reglas de categorías por edad dependen del año; el día exacto no. Mantiene los tres formatos históricos de texto si se quiere ejercitar `fprtm_parse_fecha`. |
| `insc_registro` → `dob`, nombre, contacto | Igual que arriba, coherente por `member_id`. |
| `membership_requests`, `photo_requests`, `club_info_requests` | Anonimizar nombre y correo; conservar estados y fechas. |
| `player_reg_submissions` | Anonimizar; es un formulario con datos personales completos. |

### Omitir por completo

| Tabla / dato | Motivo |
|---|---|
| `player_reg_tokens` | Tokens de registro válidos. Copiarlos crearía credenciales vivas en un entorno menos protegido. |
| `audit_log` | Contiene `old_data`/`new_data` en JSON con los datos personales **sin anonimizar**, así que sortearía todo lo anterior. Staging genera su propia auditoría. |
| Objetos de Storage (`player-photos`) | Fotografías de personas, incluidas de menores. Staging trabaja con marcadores. |
| Cuentas de `auth.users` | Staging crea las suyas. Nunca se copian credenciales. |
| Cualquier dato de pago o referencia de ATH Móvil | No hace falta para probar, y su valor de riesgo es alto. |

### Notas de implementación

- La anonimización debe correr **entre** el export y la restauración: un
  script que lea `./backup-out/<fecha>/`, transforme y escriba
  `./backup-anonimizado/<fecha>/`. Nunca sobre producción.
- Debe ser determinista (mismo `Member ID` → mismo alias) para que los datos
  sigan siendo coherentes entre tablas.
- El directorio anonimizado tampoco se sube al repositorio: sigue derivando
  de datos reales y un error de anonimización sería difícil de detectar.
- Ese script todavía **no existe**; es trabajo de Fase 1, listado en el
  alcance propuesto de `PHASE0_REPORT.md`.

---

*Documento de Fase 0. Nada de lo descrito aquí se ha ejecutado.*
