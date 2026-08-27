# SECURITY FINDINGS — Fase 0

**Estado: DOCUMENTACIÓN ÚNICAMENTE. No se ha corregido nada.**

Levantamiento hecho durante la Fase 0 sobre `ratings.ttmpr.xyz`
(repositorio `TTMPR/fprtm.ratings`, rama `claude/kileaaa-migration-plan-ccrvvk`).

No se modificó código de seguridad, ni esquema, ni políticas RLS, ni Supabase.
No se ejecutó ninguna migración. Cada hallazgo lleva una remediación
**propuesta** para la Fase 1, que requiere aprobación antes de aplicarse.

Los hallazgos marcados **BLOQUEANTE** impiden construir un Developer Mode
seguro o una multi-organización correcta: hasta que se resuelvan, no hay
frontera de privilegio sobre la que apoyarse.

---

## Resumen

| # | Severidad | Componente | Hallazgo | Bloquea |
|---|---|---|---|---|
| F-01 | **Crítica** | `index.html` · `isAdmin()` | Cualquier sesión autenticada es admin | Dev Mode, multi-org |
| F-02 | **Alta** | RLS · `Base de Datos` | La llave publicable lee email, DOB y dirección | Multi-org |
| F-03 | **Alta** | `index.html` · escrituras | El navegador escribe ratings y partidos directamente | Dev Mode |
| F-04 | **Alta** | RLS · 18 políticas | `TO authenticated USING(true) WITH CHECK(true)` | Dev Mode, multi-org |
| F-05 | Media | RLS · 8 ficheros SQL | Identidad de admin escrita a mano en las políticas | Multi-org |
| F-06 | Media | `audit_log` | Las escrituras con la llave publicable quedan como `anon` | Dev Mode |
| F-07 | Media | `backup/` | Los backups viven en el mismo proyecto Supabase | — |
| F-08 | Media | `app_settings` | Cualquier autenticado puede cambiar los interruptores | Dev Mode |
| F-09 | Baja-Media | GitHub Actions | `service_role` en secretos de un repositorio público | — |
| F-10 | Baja | Entorno | No existe staging: todo se prueba contra producción | Todo |

---

## F-01 · Cualquier sesión autenticada es administrador

**Severidad:** Crítica — **BLOQUEANTE**
**Componente:** `index.html:4889-4891`

**Comportamiento actual**
```js
// Single admin account (Joel). Any authenticated session = admin.
function isAdmin() {
  return currentUser !== null;
}
```
`isAdmin()` no comprueba identidad ni rol: devuelve `true` para cualquier
usuario con sesión iniciada. De ahí cuelga toda la interfaz privilegiada —
panel de administración, subida de resultados, membresías, papelera,
historial de auditoría (`index.html:5079-5112`), y el guard de páginas
protegidas en `showPage()` (`index.html:5407`).

**Riesgo**
Hoy el riesgo real está contenido porque sólo existe una cuenta y porque
algunas políticas RLS sí filtran por correo (F-05). Pero la contención vive
en "no hay más cuentas", no en el código. En cuanto se cree un segundo
usuario — un árbitro, un organizador, el admin de LAI — tendrá la interfaz
de administración completa. La barrera de la RLS es parcial: las tablas del
F-04 aceptan cualquier escritura autenticada.

**Remediación propuesta (Fase 1)**
Introducir roles reales (`owner` / `admin` / `arbitro` / `jugador`) como
*custom claim* en el JWT de Supabase, y reescribir `isAdmin()` para leer el
claim. El claim, no la interfaz, es lo que deben comprobar las políticas RLS.
La interfaz sólo decide qué se dibuja; la autoridad se queda en la base.

---

## F-02 · Datos personales legibles con la llave publicable

**Severidad:** Alta — **BLOQUEANTE para multi-organización**
**Componente:** RLS de `public."Base de Datos"`

**Comportamiento actual**
La política de SELECT de `Base de Datos` es `USING (true)`: filtra filas, no
columnas. Con la llave publicable que va incrustada en `index.html:4882`
(`sb_publishable_…`, pensada para ser pública) cualquiera puede pedir
`select=*` y recibir `Email`, `Home Address` y `Date of Birth` de los 537+
jugadores del registro.

El propio repositorio ya lo documenta en la cabecera de
`sql/create_api_publica.sql`:

> *"Cualquiera con la llave publicable puede pedir select=* y obtener Email,
> Home Address y Date of Birth completos. El index.html se auto-limita a
> columnas no sensibles por disciplina, pero eso no es una barrera."*

Las vistas `api_jugadores`, `api_clubes` y `api_torneos` se crearon
justamente para resolverlo de cara a terceros, y lo hacen bien — pero la
tabla base sigue abierta, así que la vista es una alternativa, no una
restricción.

**Riesgo**
Exposición de datos personales de menores de edad incluidos (el registro
guarda fecha de nacimiento y el sistema tiene categorías desde sub-7).
La llave está en un repositorio público y en el código de una web pública:
extraerla es trivial y no deja rastro en `audit_log`.

**Remediación propuesta (Fase 1)**
Revocar el SELECT de `anon` sobre `Base de Datos` y dejar las vistas `api_*`
como único camino de lectura pública. La aplicación pasa a leer los datos
completos con el JWT de sesión. Requiere revisar antes qué consultas de
`index.html` leen columnas sensibles con la llave publicable, para no romper
la interfaz pública en el mismo cambio.

---

## F-03 · El navegador escribe ratings y partidos directamente

**Severidad:** Alta — **BLOQUEANTE para Developer Mode**
**Componente:** `index.html:7699` (`subirApplyRatings`)

**Comportamiento actual**
El cierre de ratings de un torneo ocurre íntegramente en el cliente: el
navegador calcula los deltas, hace `sbPost('partidos', …)` por cada partido,
un `sbPatch('Base de Datos', …)` por jugador y un `sbPost('resultados_evento', …)`
por lotes. No hay ninguna operación de servidor que valide el conjunto.

`sbPatch`/`sbPost` intentan usar el JWT de la sesión y caen a la llave
publicable si no hay sesión (`index.html:5022-5029`).

**Riesgo**
La integridad del rating depende de que el cliente se comporte. Cualquiera
con una sesión válida puede escribir cualquier rating con una petición
manual, sin pasar por `getPoints()`. Además, un fallo a media aplicación
(red, pestaña cerrada) deja el torneo a medio cerrar: algunos jugadores
actualizados y otros no, sin transacción que lo revierta.

**Remediación propuesta (Fase 1)**
No cambiar el algoritmo — sólo dónde se ejecuta. Mover el cierre a una
función `SECURITY DEFINER` (o Edge Function) que reciba los partidos y
aplique el lote de forma atómica, con los mismos cálculos. Las políticas de
UPDATE sobre `Base de Datos` pasan a rechazar escrituras directas de rating
desde el cliente. Es prerequisito de la Fase 7 del plan de migración.

---

## F-04 · Dieciocho políticas aceptan cualquier escritura autenticada

**Severidad:** Alta — **BLOQUEANTE**
**Componente:** RLS, 18 políticas en `create_*.sql` y `sql/*.sql`

**Comportamiento actual**
Patrón repetido en `app_settings`, `clubs`, `articulos`,
`club_info_requests`, `insc_registro` y otras:

```sql
CREATE POLICY "authenticated_write_…" ON public.<tabla>
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);
```

Combinado con F-01, "estar autenticado" equivale a control total sobre esas
tablas, tanto desde la interfaz como desde peticiones directas.

**Riesgo**
No hay separación posible entre roles mientras estas políticas existan: un
árbitro con sesión podría reescribir inscripciones o borrar clubes. También
impide la multi-organización, porque no hay predicado de pertenencia: un
admin de LAI vería y escribiría datos de FPTM.

**Remediación propuesta (Fase 1)**
Sustituir `USING (true)` por un predicado de rol basado en el claim de F-01.
En la Fase 2 esos mismos predicados se amplían con `org_id`. Conviene
hacerlo tabla por tabla, verificando la interfaz tras cada una, en vez de en
un solo cambio masivo.

---

## F-05 · Identidad de administrador escrita a mano en las políticas

**Severidad:** Media
**Componente:** 8 ficheros SQL (`fix_rls_torneos_borrar.sql`,
`fix_base_datos_rls.sql`, `setup_fprtm_database.sql`,
`club_change_requests.sql`, `create_photo_requests.sql`,
`sql/create_audit_log.sql`, entre otros)

**Comportamiento actual**
Unas 20 políticas comprueban `auth.jwt() ->> 'email' = 'joel@ttmpr.xyz'`.
Es hoy la única barrera real de privilegio del sistema — y es también la que
sostiene la contención descrita en F-01.

**Riesgo**
Un cambio de correo, una baja o una segunda persona en administración
dejan el sistema sin admin efectivo, o exigen editar y reejecutar veinte
políticas a mano en el editor SQL. `fix_rls_torneos_borrar.sql:60` ya
reconoce el problema en un comentario. Es además incompatible con la
multi-organización: no hay un solo correo que sea admin de todas.

**Remediación propuesta (Fase 1)**
Migrar a un claim de rol y, si hace falta granularidad, a una tabla
`admins`/`org_members` consultada por las políticas. Retirar el correo
literal en el mismo cambio que introduce el claim, para no quedarse sin
ninguna de las dos barreras a mitad de camino.

---

## F-06 · La auditoría atribuye las escrituras a `anon`

**Severidad:** Media — **BLOQUEANTE para Developer Mode**
**Componente:** `sql/create_audit_log.sql`

**Comportamiento actual**
El trigger `fn_audit()` registra `auth.jwt() ->> 'email'` como actor, o
`'anon'` si la petición llegó con la llave publicable. La cabecera del
fichero ya lo documenta:

> *"Las escrituras que la app hace con la anon key (la mayoría de sbPatch/sbPost
> actuales) quedan como 'anon'. Como el único admin es Joel, en la práctica
> 'anon' en tablas de admin = Joel."*

**Riesgo**
Esa equivalencia deja de ser cierta en cuanto haya un segundo usuario, y el
registro de auditoría pierde su valor justo cuando empieza a hacer falta.
Un Developer Mode sin atribución fiable es un agujero: la premisa de la Fase 1
es que toda acción privilegiada quede firmada con un correo real.

**Remediación propuesta (Fase 1)**
Hacer que todas las escrituras privilegiadas viajen con el JWT de sesión
(`sbGetAuth` ya existe como precedente en `index.html:4943`) y considerar
rechazar escrituras anónimas en las tablas auditadas. El `audit_log` en sí
está bien diseñado: es append-only y sólo escribe el trigger.

---

## F-07 · Los backups viven en el mismo proyecto que protegen

**Severidad:** Media
**Componente:** `.github/workflows/weekly-backup.yml`, `backup/export_backup.mjs`

**Comportamiento actual**
El export semanal sube a un bucket privado `backups` **del mismo proyecto
Supabase** (`qrvyfdpwtearfpjruwja`). La decisión está razonada y es correcta
en lo que perseguía: evitar publicar datos personales en un repositorio
público o en artifacts de Actions.

**Riesgo**
Es un único punto de fallo. Un borrado del proyecto, una suspensión de la
cuenta o una credencial `service_role` comprometida se lleva por delante los
datos **y** sus copias. Tampoco hay retención automática: el propio README
lo señala.

Nota aparte: el ejercicio de restauración que documenta `backup/README.md`
no consta como realizado. Un backup no restaurado nunca es un backup
verificado.

**Remediación propuesta (Fase 1)**
Añadir un destino fuera de Supabase (almacenamiento cifrado de un tercero o
una copia cifrada fuera de línea) y ejecutar el ejercicio de restauración
contra el proyecto de staging de la Fase 0. No sustituye al bucket actual:
lo duplica.

---

## F-08 · Los interruptores del sistema son escribibles por cualquier autenticado

**Severidad:** Media — **BLOQUEANTE para Developer Mode**
**Componente:** `create_app_settings.sql`, `app_settings`

**Comportamiento actual**
`app_settings` es legible por todos y escribible por cualquier autenticado
(caso concreto de F-04). Contiene interruptores de operación:
`inscripciones_open`, `torneo_archivado`, `insc_ignorar_deadline`,
`insc_parte_abierta`, `insc_equipos_reserva_horas`.

**Riesgo**
Son controles de negocio con efecto inmediato y público: abrir o cerrar
inscripciones, saltarse fechas límite, archivar un torneo. Sin roles, no hay
diferencia entre consultarlos y cambiarlos.

**Remediación propuesta (Fase 1)**
Escritura restringida al claim de administración. Es además la tabla donde
debe vivir el interruptor de apagado del Developer Mode
(`dev_mode_enabled`), así que necesita su propia política antes de que
exista el modo.

---

## F-09 · `service_role` en los secretos de un repositorio público

**Severidad:** Baja-Media
**Componente:** `.github/workflows/weekly-backup.yml`

**Comportamiento actual**
El backup semanal usa `secrets.SUPABASE_SERVICE_ROLE_KEY`. La clave
`service_role` ignora la RLS por completo. El workflow está bien planteado
—no publica el export como artifact, precisamente porque el repositorio es
público— pero cualquiera con permiso de escritura en el repositorio puede
abrir un workflow que imprima el secreto.

**Riesgo**
La superficie es el conjunto de personas con acceso de escritura y la
posibilidad de un PR malicioso desde un fork si la configuración de Actions
lo permitiera.

**Remediación propuesta (Fase 1)**
Verificar que Actions no expone secretos a PRs de forks, restringir quién
puede aprobar workflows, y considerar mover el backup a un ejecutor propio.
Rotar la clave cuando se haga la revisión de accesos.

---

## F-10 · No existe entorno de staging

**Severidad:** Baja como vulnerabilidad, alta como riesgo operativo — **BLOQUEANTE**
**Componente:** Infraestructura

**Comportamiento actual**
Un único proyecto Supabase. Toda prueba de esquema, política o dato ocurre
contra producción. El propio `backup/README.md` pide crear un proyecto de
prueba para el ejercicio de restauración, y no consta que exista.

**Riesgo**
Cualquier corrección de las anteriores se prueba sobre datos reales. Endurecer
la RLS sin un sitio donde ensayarlo es exactamente el cambio que rompe la
web pública un viernes.

**Remediación propuesta (Fase 1)**
Crear el proyecto de staging descrito en `docs/PHASE0_BACKUP_AND_STAGING.md`
**antes** de tocar ninguna política. Es el primer paso de la Fase 1, no un
extra.

---

## Qué impide hoy un Developer Mode seguro

El Developer Mode del plan de migración se apoya en cuatro cosas que ahora
mismo no existen:

1. **Una frontera de privilegio.** F-01 y F-04: no hay diferencia entre
   usuarios, así que "modo desarrollador" no podría significar nada distinto
   de "sesión iniciada".
2. **Atribución fiable.** F-06: las acciones privilegiadas quedan como
   `anon`, así que el modo no podría firmar lo que hace.
3. **Un entorno al que apuntar.** F-10: la capacidad más valiosa del modo es
   cambiar a staging, y no hay staging.
4. **Un interruptor de apagado protegido.** F-08: el kill switch viviría en
   `app_settings`, hoy escribible por cualquiera.

## Qué impide hoy la multi-organización

- **F-02 y F-04**: sin predicados de pertenencia en las políticas, un segundo
  inquilino leería y escribiría los datos del primero.
- **F-05**: no hay un correo único que pueda ser administrador de todas las
  organizaciones.

---

*Documento de Fase 0. Ninguna de estas remediaciones se ha aplicado.
Requieren aprobación explícita y pertenecen a la Fase 1.*
