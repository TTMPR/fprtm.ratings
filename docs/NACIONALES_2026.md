# Campeonatos Nacionales 2026 — Inscripciones

Guía operativa de las inscripciones a los Campeonatos Nacionales de Tenis de
Mesa 2026 (12, 13, 19 y 20 de diciembre · Albergue Olímpico, Salinas).

| Pieza | Archivo |
|---|---|
| Página pública | `nacionales.html` (enlazada desde la tarjeta de `index.html`) |
| Panel de admin | `nacionales-admin.html` (entra por `admin.html?next=nacionales`) |
| Base de datos | `sql/nacionales_2026.sql` |
| Reglamento con los ajustes | `docs/Nacionales_2026_Reglamento.docx` (el mismo texto está dentro de `nacionales.html`) |
| Logo | `Logo_Campeonatos_Nacionales_2026.webp` |

---

## 1. Antes de abrir

1. En el SQL Editor de Supabase, correr **`sql/nacionales_2026.sql`** completo.
   Termina con `nacionales_2026 OK`. Se puede volver a correr sin perder
   inscripciones ni los slugs de Stadium.
2. Correr `sql/security/verify_access_controls_20261020.sql` y confirmar
   `security_baseline = PASS`.
3. Entrar a `nacionales-admin.html` y pulsar **Abrir inscripciones**. Las
   inscripciones quedan **cerradas por defecto** después de la migración.

La migración no toca ninguna tabla existente: crea `nac_eventos`,
`nac_inscripciones`, `nac_inscripcion_eventos` y `nac_verificaciones`, y dos
claves nuevas en `app_settings` (`nacionales_inscripciones_open`,
`nacionales_ignorar_deadline`).

---

## 2. Cómo se inscribe un jugador

1. **¿Quién juega?** Busca por Member ID o nombre (directorio público
   `api_busqueda_membresia`). Antes de verificar solo se ve nombre, Member ID
   y club.
2. **Fecha de nacimiento.** Tiene que coincidir con "Date of Birth" del
   registro de la FPTM. Hasta entonces no se ve rating, membresía ni
   categorías. Después de **5 fechas equivocadas en 15 minutos** ese Member ID
   queda bloqueado 15 minutos.
3. **Membresía.** Tiene que estar vigente hasta el **20 de diciembre de 2026**.
   Si vence antes, aunque hoy aparezca activo, la página le explica por qué y
   lo manda a renovar (`membresia.html?type=renewal`). Sin membresía no puede
   seguir.
4. **Reglamento.** Tiene que deslizarlo hasta el final para poder marcar la
   casilla de aceptación (incluye la elegibilidad suya y de su pareja). Sin
   aceptarlo no se habilitan las categorías.
5. **Categorías.** Ver §3.
6. **Enviar.** El servidor valida todo otra vez y calcula el total. La página
   muestra el número de inscripción, el total y cómo pagar: ATH Móvil Business
   `/fprtm` y evidencia por WhatsApp a Joel Vega (con el mensaje ya escrito).

Un jugador puede volver más tarde y añadir categorías (otra inscripción, otro
pago). Lo que ya tiene inscrito aparece marcado y cuenta para horarios y para la
categoría natural.

---

## 3. Reglas programadas (servidor y página)

| Regla | Cómo funciona |
|---|---|
| Edad | Por año natural: edad al 31 de diciembre de 2026. |
| Natural por edad | La menor que admite su edad: 7 (mixto), 9, 11, 13, 15, 19. |
| Natural por rating | La menor que admite su rating: 1500 … 1900. Con más de 1900 no tiene categoría de rating. |
| Superiores por rating | Hasta 2 por encima de la natural. Se habilitan al escoger la natural. |
| Superior por edad | Solo 13 y menos / 15 y menos → 19 y menos, con la natural. Cualquier otra excepción la autoriza el Director Técnico. |
| Natural obligatoria | No se puede escoger una superior sin la natural, ni quitar la natural mientras haya una superior escogida. |
| Horario | Nunca dos eventos el mismo día a la misma hora, incluido Dobles (p. ej. Dobles M/F y Rating 1600, domingo 9:00 a.m.). |
| Abierto | Por sexo, sin restricción de edad ni rating. |
| Seniors | 40 años o más al 31 de diciembre. |
| Dobles | Un jugador inscribe a la pareja y paga los $40. La pareja tiene que tener membresía vigente hasta el 20 de diciembre, ser del sexo que pide el evento (Mixtos: uno y una), no estar ya en ese evento ni inscrita a la misma hora. Las parejas no llevan nombre. |
| Precios | $20 por categoría, $25 el Abierto, $11 los 7 años o menos, $40 por pareja de dobles. Sin multas ni recargos. |
| Fecha límite | Viernes 4 de diciembre de 2026, 11:00 p.m. AST (o la prórroga del admin). |

---

## 4. Panel de admin (`nacionales-admin.html`)

Mismo usuario administrador que `admin.html` (UID fijo). Si no hay sesión,
manda a `admin.html?next=nacionales` y regresa al panel después de entrar.

- **Abrir / cerrar** y **prórroga** después de la fecha límite.
- **Aprobar pago**: solo después de recibir la evidencia de ATH Móvil. Solo las
  inscripciones **aprobadas** salen en el CSV de Stadium y en la vista de
  Kileaaa.
- **Cancelar**: la inscripción completa o una sola categoría. Pide una nota
  (por ejemplo, "crédito para el próximo evento").
  - Si se cancela una **categoría natural** y el jugador **sigue** en una
    superior que depende de ella, el panel avisa y, al confirmar, la natural
    queda como **"Cancelada · penalidad (3 W/O)"** (reglamento §11:
    penalidad de rating estimada por la Mesa Técnica y 3 W/O). No se borra
    nada: queda el registro para la Mesa Técnica.
  - Si se cancelan la natural y la superior juntas, no hay penalidad.
- **Exportar**
  - *Inscritos (CSV)*: todo lo no cancelado, una fila por jugador y
    categoría, con estado de pago.
  - *Stadium · jugadores (CSV)*: solo aprobadas, formato de importación de
    jugadores de Stadium (`membershipIds = fptm|ID`, `clubId` de Stadium,
    `events` con los slugs).
  - *Stadium · dobles (CSV)*: solo aprobadas, una fila por pareja
    "Nombre / Nombre", sembrada por la suma de rating.
- **Slugs de Stadium**: el torneo todavía no existe en Stadium. Cuando se cree,
  copiar el slug de cada evento (*Admin → Edit Event Settings*) en la tabla
  "Por categoría"; se guarda al salir del campo. Mientras una categoría no
  tenga slug, el CSV la omite y lo avisa.

Las inscripciones pendientes que nunca se paguen siguen ocupando a la pareja y
el horario hasta que el admin las cancela.

---

## 5. Kileaaa

Kileaaa (Railway) arma el torneo desde su app. Para leer a los inscritos
aprobados, ya en sus categorías:

```sql
SELECT * FROM public.nac_inscritos_aprobados;   -- evento, member_id, pareja_member_id, …
SELECT * FROM public.nac_eventos ORDER BY orden; -- las 22 categorías
```

La vista solo devuelve inscripciones **aprobadas** y categorías **activas**.
Es *security invoker*: la ve el administrador autenticado o `service_role`
(servidor de Kileaaa). `anon` no tiene acceso. Los jugadores se enlazan por
**Member ID**; en dobles sale una fila por pareja.

---

## 6. Seguridad

- Ninguna función `SECURITY DEFINER` vive en `public`: las que leen
  "Base de Datos" están en `internal_security` y PostgREST solo expone
  envolturas `SECURITY INVOKER` (`nac_estado`, `nac_verificar`, `nac_parejas`,
  `nac_inscribir` y las `nac_admin_*`).
- El navegador nunca escribe en las tablas. Identidad (Member ID + fecha de
  nacimiento), membresía, reglas, parejas y total se validan en el servidor.
- La búsqueda de pareja nunca devuelve fecha de nacimiento ni sexo.
- Las funciones `nac_admin_*` exigen el UID administrador.
- La migración termina con comprobaciones que fallan si algo de esto se rompe.
