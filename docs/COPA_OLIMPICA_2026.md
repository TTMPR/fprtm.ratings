# Copa Olímpica 2026 — Inscripciones por equipos

Guía operativa del módulo de inscripción por equipos: qué hay que correr
antes de abrir, qué reglas están programadas y qué hace el admin cada día.

**Torneo:** 19 y 20 de septiembre de 2026 · Centro de Convenciones de PR
**Organizan:** COPUR y FPTM · **Cupo:** 64 equipos · **Cierre:** viernes 11
de septiembre, 10:00 p.m. AST (o antes si se llenan los 64).

---

## 1. Antes de abrir — dos pasos

### Paso 1: correr el SQL

En **Supabase → SQL Editor**, pegar y ejecutar `sql/create_insc_equipos.sql`
completo. Es seguro re-ejecutarlo: no borra datos.

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
| **⟳ Liberar cupos vencidos** | Expira reservas vencidas sin pago y sube la lista de espera. Corre sola en cada inscripción nueva; el botón es para forzarla. |
| **⬇ CSV** | Todos los equipos con contacto, montos y referencias. |

**Filtro "🔥 Reserva por vencer (24 h)"**: la lista de a quién llamar hoy.

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

## 5. Lo que todavía no está

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

## 6. Volver a un torneo individual

El flujo individual por categorías (Cidra, Morovis) sigue intacto en el
código, solo apagado. Para el próximo torneo de ese tipo:

1. Cambiar `TORNEO_MODO` a `'individual'` en `index.html`.
2. Actualizar las constantes del torneo (`TORNEO_ACTIVO`, sede, fechas,
   logo) y `INSC_CATEGORIES`.

No hay que deshacer nada de la Copa: sus datos quedan en `insc_equipos`
guardados bajo el nombre del torneo.
