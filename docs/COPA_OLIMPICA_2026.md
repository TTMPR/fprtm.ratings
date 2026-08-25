# Copa Olímpica 2026 — Inscripciones por equipos

Guía operativa del módulo de inscripción por equipos: qué hay que correr
antes de abrir, qué reglas están programadas y qué hace el admin cada día.

**Torneo:** 19 y 20 de septiembre de 2026 · Centro de Convenciones de PR
**Organizan:** COPUR y FPTM · **Cupo:** 64 equipos · **Cierre:** viernes 11
de septiembre, 10:00 p.m. AST (o antes si se llenan los 64).

---

## 1. Antes de abrir — dos pasos

### Paso 1: correr el SQL

En **Supabase → SQL Editor**, pegar y ejecutar, en este orden:

1. `sql/create_insc_equipos.sql`
2. `sql/create_busca_companero.sql` (el tablón "Busco Compañero")

Ambos son seguros de re-ejecutar: no borran datos.

Al final imprime los cupos de las tres divisiones. Si ves esto, quedó bien:

```
 division |   nombre   | precio | max_equipos | ocupados | disponibles
 div1     | División 1 | 100.00 |          12 |        0 |          12
 div2     | División 2 |  80.00 |          20 |        0 |          20
 div3     | División 3 |  70.00 |          32 |        0 |          32
```

### Paso 2: abrir las inscripciones

En el panel de admin del sitio:

1. **Reactivar Torneo** — si la tarjeta dice "Reactivar", el torneo está
   archivado y el público solo ve la cuenta regresiva.
2. **Inscripciones** — clic en la tarjeta hasta que diga *"Abiertas"*.

Mientras estén cerradas, el admin igual ve el formulario (con un aviso de
"Vista previa") para poder probarlo sin que nadie más entre.

---

## 2. Las reglas que están programadas

| Regla | Cómo funciona |
|---|---|
| **Equipos de 2** | Una sola persona inscribe a los dos. No hay que confirmar del otro lado. |
| **División automática** | Sale del rating combinado. **No se puede escoger** ni jugar hacia arriba. |
| **Rating congelado** | Se guarda el rating de ambos al momento de inscribir. Si cambia después, el equipo juega y paga lo que vio. |
| **Un equipo por jugador** | Nadie puede aparecer en dos equipos del torneo. |
| **Cupo reservado 48 h** | Se toma al inscribir. Si no entra pago, se libera y entra el primero de la lista de espera. |
| **Abono parcial protege** | Cualquier monto > 0 evita que la reserva expire sola. |
| **Lista de espera** | División llena → el equipo entra igual, en espera, y **no paga** hasta tener cupo. |
| **Invitado sin rating** | El equipo queda en *"división por asignar"* y no ocupa cupo de nadie hasta que el admin le asigne una. |
| **Cupo sin pareja** | Solo División 1 y solo con rating 2000+. Ocupa cupo desde que se compra. Ver sección 5. |
| **Precio fijo** | Sin recargo por no tener membresía. |

Divisiones: **D1** 3800+ · $100 · 12 equipos — **D2** 3400–3799 · $80 · 20
equipos — **D3** 3399 o menos · $70 · 32 equipos.

### Por qué el cupo no se puede pasar

Toda inscripción entra por `inscribir_equipo()`, que corre con un *advisory
lock* por torneo: dos capitanes pulsando "Inscribir" en el mismo instante se
ponen en fila, no compiten. Probado con ocho inserciones simultáneas contra
dos cupos libres: exactamente dos reservas y seis en lista de espera.

El público **no tiene permiso** sobre la tabla `insc_equipos`. Solo puede
leer dos vistas que no contienen email, teléfono, referencia ni montos, y
solo puede escribir a través de esa función. La llave anon del código no
sirve para sacar datos de contacto.

---

## 3. El día a día — panel "Gestionar Equipos"

La tarjeta lleva una insignia naranja con **cuántos equipos tienen la reserva
venciendo en menos de 24 horas**. Ese es el número que hay que atender.

| Acción | Qué hace |
|---|---|
| **💵 Registrar pago** | Pide monto y referencia. Si cubre el costo, el equipo pasa a *confirmado* y se le apaga el reloj. Si es abono, mantiene el cupo sin darlo por pagado. |
| **⏱ +48 h** | Extiende la reserva de alguien que avisó que va a pagar. |
| **🎯 Asignar división** | Solo para equipos con invitado sin rating. Fija división y costo; si está llena, ofrece lista de espera. |
| **✕ Cancelar** | Libera el cupo y promueve de inmediato al primero en espera. |
| **⚖️ Aprobar / ⬇ Bajar** | Solo en equipos en revisión técnica: la Dirección Técnica decide si acepta la excepción o baja al equipo ajustando el costo. |
| **🎫 Liberar y dar crédito** | Para el que compró cupo y nunca nombró compañero: libera el cupo y registra el dinero como crédito. |
| **⟳ Liberar cupos vencidos** | Expira reservas vencidas sin pago y sube la lista de espera. Corre sola en cada inscripción nueva; el botón es para forzarla. |
| **⬇ CSV** | Todos los equipos con contacto, montos y referencias. |

**Filtro "🔥 Reserva por vencer (24 h)"**: la lista de a quién llamar hoy. La
insignia de la tarjeta cuenta esas reservas **más** los equipos parados en
revisión técnica esperando decisión.

### Conciliar pagos de ATH Móvil

La pantalla de confirmación le pide al capitán poner **"Copa #<número>"** en
el concepto del pago. Ese número es el `id` del equipo y sale en el panel, así
que el pago se busca por ahí en vez de adivinar por nombre.

---

## 4. Ajustes sin tocar código

En Supabase, tabla `app_settings`:

| Clave | Para qué | Valor actual |
|---|---|---|
| `insc_equipos_cierre` | Fecha límite (ISO 8601). Después de esa fecha la función rechaza inscripciones. | `2026-09-11T22:00:00-04:00` |
| `insc_equipos_reserva_horas` | Horas de reserva antes de perder el cupo. | `48` |
| `inscripciones_open` | Abre/cierra todo. Lo maneja el botón del panel. | — |

Los cupos y precios por división se cambian en la tabla `insc_divisiones`.
Subir un cupo hace entrar automáticamente a los de la lista de espera la
próxima vez que corra "Liberar cupos".

> La fecha límite también está en el JavaScript (`COPA_DEADLINE`) para pintar
> el texto en pantalla. Si la federación mueve la fecha, hay que cambiarla en
> los dos sitios: `app_settings` manda de verdad, el código solo se muestra.

---

## 5. Comprar cupo sin tener pareja (División 1)

Un jugador fuerte que quiere asegurar su sitio antes de tener con quién jugar
puede **comprar el cupo y nombrar al compañero después**.

| Regla | Valor |
|---|---|
| Divisiones que lo admiten | Solo **División 1** |
| Rating mínimo del solicitante | **2000** — verificado contra la base, no contra lo que mande el navegador |
| Si la división está llena | No se puede reservar (no hay lista de espera para un cupo sin pareja) |
| Plazo de pago | El mismo de siempre: 48 h o el cupo vuelve al torneo |
| Plazo para nombrar compañero | Hasta el cierre |

Aparece solo a quien califica: en el encasillado del Jugador 2, cuando el
Jugador 1 ya está escogido, su rating pasa de 2000 y queda cupo en D1.

**Lo que compra es el cupo, no la división.** Cuando nombra a su compañero:

- **Combinado ≥ 3800** → el equipo queda normal, en División 1.
- **Combinado < 3800** (o el compañero es un invitado sin rating) → el equipo
  pasa a **revisión técnica**. Ni sube ni baja solo: es dinero ya cobrado, así
  que decide la Dirección Técnica desde el panel.
  - **⚖️ Aprobar excepción** — se queda en División 1 tal cual.
  - **⬇ Bajar de división** — va a la que le toca por rating combinado, se
    ajusta el costo y el panel te dice cuánto devolverle. Si la división de
    destino está llena, queda en lista de espera. El cupo que suelta en D1
    pasa de inmediato al primero en espera.

**Si llega el cierre sin compañero:** botón **🎫 Liberar y dar crédito** en el
panel. El cupo vuelve al torneo (entra el primero de la lista de espera) y lo
pagado queda registrado como crédito a favor del jugador, visible en el panel
y en el CSV.

> Quien compra cupo **sí puede publicar en "Busco Compañero"** — es quien más
> lo necesita. Su anuncio lleva una insignia *"Ya tiene cupo en División 1"*,
> que es el mejor argumento posible para que alguien se le una. La pantalla de
> confirmación de la reserva le ofrece publicar de una vez.

---

## 6. Tablón "Busco Compañero"

Tercera pestaña, junto a *Inscribirse* y *Ver Inscritos*. Quien no tiene
pareja publica que busca, y los demás lo ven y le escriben directo.

Lo que lo hace útil y no un grupo de WhatsApp con más pasos: **el visitante
escoge su nombre primero**, y entonces el tablón le dice, con cada jugador de
la lista, en qué división caerían juntos y cuánto pagarían — agrupado de la
división más alta a la más baja. Es una pregunta que solo esta plataforma
puede contestar, porque la división sale del rating combinado.

### Contacto — decisión de la federación

El contacto es **público y opcional**. Quien publica escoge WhatsApp, email o
"por la FPTM". Lo que escoja queda visible para cualquiera que abra la página,
no solo para jugadores inscritos, y el formulario se lo advierte antes de
publicar.

Quede claro para poder decidir distinto más adelante: cualquiera que lea el
código fuente del sitio obtiene la llave anon y con ella esa lista de
contactos. Es el precio de que el tablón funcione de un vistazo. Si algún día
prefieren que no, el cambio es servir el contacto solo tras una acción
("Me interesa") en vez de en la lista.

### Menores de edad

**El contacto de un menor de 18 no se publica nunca.** Su anuncio aparece,
pero dice "contacta a la FPTM" y la federación conecta con la madre, padre o
encargado. El contacto sí se ve en el panel de admin — es lo que hace posible
ese "contacta a la FPTM".

Esa decisión **no la toma el navegador**: `publicar_busca_companero()` la
calcula contra la fecha de nacimiento de `Base de Datos`. Aunque el formulario
mandara un teléfono y declarara que el jugador es adulto, el servidor lo
descarta igual. Probado.

Si la base no tiene fecha de nacimiento utilizable, el formulario le pide al
jugador confirmar que tiene 18 o más. Sin esa confirmación, se publica sin
contacto — preferimos un anuncio sin teléfono a publicar el de un menor por
no saberlo.

### Se mantiene solo

- Al aparecer en un equipo inscrito, el anuncio **desaparece del tablón**.
  Nadie tiene que acordarse de retirarlo. La fila queda `activo` en la tabla,
  así que si luego cancelan el equipo, el anuncio reaparece solo.
- Quien ya tiene equipo no puede publicar.
- Un anuncio activo por persona: volver a publicar reemplaza el anterior.
- Botón "Ya conseguí compañero" para retirarlo a mano.

### Admin

Sección desplegable al final de *Gestionar Equipos*: la lista completa con el
contacto de todos (menores incluidos) y un botón para **ocultar** cualquier
anuncio abusivo o duplicado, y reactivarlo.

> Se instala con `sql/create_busca_companero.sql`. Requiere que
> `sql/create_insc_equipos.sql` ya esté corrido.

---

## 7. Lo que todavía no está

- **Export a Stadium Compete.** Stadium no importa equipos; el torneo se
  cargaría con el truco de dobles (`"Nombre / Nombre"` como una sola entrada,
  sembrada por rating combinado), igual que `exportDoblesStadium()`. Queda
  pendiente por decisión de la federación.
- **Avisos automáticos por email.** Hoy el contacto se recoge y se muestra en
  el panel, pero avisar de un cupo por vencer o de una promoción desde la
  lista de espera es manual.
- **Llaves y grupos.** El sorteo (4 grupos de 3, 5 de 4, 8 de 4) no está
  programado; se hace en Stadium.

---

## 8. Volver a un torneo individual

El flujo individual por categorías (Cidra, Morovis) sigue intacto en el
código, solo apagado. Para el próximo torneo de ese tipo:

1. Cambiar `TORNEO_MODO` a `'individual'` en `index.html`. La pestaña
   "Busco Compañero" se oculta sola — en un torneo individual nadie busca
   compañero.
2. Actualizar las constantes del torneo (`TORNEO_ACTIVO`, sede, fechas,
   logo) y `INSC_CATEGORIES`.

No hay que deshacer nada de la Copa: sus datos quedan en `insc_equipos`
guardados bajo el nombre del torneo.
