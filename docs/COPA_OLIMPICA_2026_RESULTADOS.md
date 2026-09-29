# Copa Olímpica 2026 — Resultados para el rating

Cómo se convirtieron los resultados por equipos de Stadium en partidos
individuales que el rating puede usar, y qué quedó fuera.

---

## 1. Qué subir y cómo

Archivo: **`copa_olimpica_2026_individuales.csv`** (320 partidos de sencillos).

En el sitio: **Subir resultados**

1. **Nombre del torneo:** `Copa Olímpica 2026`
2. **Fecha:** `2026-09-19` (primer día)
3. **Categoría:** vacía (el archivo trae la división de cada partido)
4. Subir el CSV → debe decir *"320 partidos detectados"* y 4 categorías:
   Division 3 (128), Division 2 (122), Division 1 (51),
   Division 3 - Consolación (19). **Sin partidos omitidos.**
5. **Procesar** → revisar la vista previa → Guardar borrador → Publicar.

Súbelo **una sola vez y completo**. El rating de cada partido se calcula
contra el rating con que el jugador llegó al torneo, así que no se puede
subir por partes.

`copa_olimpica_2026_pendientes.csv` **no se sube** tal como está (ver §3).

---

## 2. De dónde sale cada dato

Hay dos fuentes de Stadium y ninguna sirve sola:

| Fuente | Qué trae | Qué le falta |
|---|---|---|
| Export CSV de partidos (`stadium-export-matches-default_11.csv`) | Un renglón por partido **de equipos**, con todos los games seguidos (11-8, 5-11, …) | Quién jugó cada individual |
| Página *Matches* del admin (copiada y pegada) | Cada individual: jugadores con su Member ID y games ganados (3-1) | Los puntos de cada game |

Se unieron así:

- Cada partido de equipos de la página se emparejó con su renglón del CSV
  (mismo par de equipos, división, llave y ronda). Emparejaron los 139.
- Como la página dice cuántos games tuvo cada individual (3-1 = 4 games), se
  cortó la lista de games del CSV en ese orden. **En los 135 partidos con
  detalle, cada corte coincidió exacto con quién ganó cada game.**
- Los games ganados de los individuales suman el resultado del equipo en
  los 135 (ej. 3-1).

Detalles de formato de Stadium que hay que saber:

- `scores` viene desde el lado del **ganador del partido de equipos**;
  `gameScores` viene desde el **equipo A**. En el archivo final ambos quedan
  desde el ganador del individual, que es lo que espera el importador.
- Un game 11-0 aparece como `0` y uno 0-11 como `-0`.

Cambios de nombre, para que el sitio lo muestre bien:

- Consolación se sube como categoría aparte (`Division 3 - Consolación`,
  llave `Llave Consolación`). Si se deja como `Division 3`, sus cuartos y
  semis salen mezclados con los de la llave principal.
- `Third Place` → `3rd Place`, que es el nombre que el sitio ordena y traduce
  como "Tercer lugar".

---

## 3. Qué quedó fuera y por qué

| Motivo | Cantidad |
|---|---|
| Dobles (no cuentan para rating) | 131 |
| Individuales no jugados (0-0, el equipo ya había ganado 3) | 179 |
| Partidos de equipo por **default**: *Best friends* (equipo 49) vs. Las Bravas, Los Noris y Los Handymen, grupo 6 de la D3 | 3 partidos |
| Individual con retiro `(RET)` (era un dobles) | 1 |
| Tercer lugar de Consolación D3 (Puntos Largos SS vs. Ping y Pong): *Not Submitted*, no se jugó | 1 partido |
| Partidos de equipo **sin detalle de individuales** en Stadium | 4 partidos |
| Individuales con un jugador **sin Member ID de la FPTM** | 29 (en `pendientes`) |

### Partidos sin detalle (no se pueden atribuir a nadie)

Stadium tiene el marcador pero no quién jugó cada individual:

- D2 · Grupo 1 (B vs. C): Camila/Danelys Cruz Rosario 3-1 Doble impacto
- D2 · Grupo 2 (B vs. C): la combi platina 3-2 Los Pelus
- D2 · Round of 16 #5: Súper Vega Brothers 3-0 Net Killers
- D2 · Round of 16 #6: Camila/Danelys Cruz Rosario 3-1 Tom y Jerry

Si alguien completa las alineaciones en Stadium, se pueden añadir.

### Jugadores sin Member ID de la FPTM

Estos cuatro se crearon directamente en Stadium, sin el número de la FPTM:

| Jugador | Equipo | Individuales |
|---|---|---|
| Pagan Diaz, Keilymar | Los Proceres (D3) | 9 |
| Colon, Fernando | Los Proceres (D3) | 9 |
| Arroyo, Victor | Los Arroyo (D3, Morovis) | 6 |
| Arroyo Martinez, Kennuel | Los Arroyo (D3, Morovis) | 5 |

Sus 29 individuales están en `copa_olimpica_2026_pendientes.csv`, con la
columna de membresía vacía del lado de ellos. Si tienen número en la base de
datos, se pone `fptm|<Member ID>` en esa celda y se sube **junto** con el
archivo principal (se pueden arrastrar los dos a la vez; el sitio los une en
un solo lote). Si no son miembros, esos partidos no cuentan, tampoco para
sus 20 rivales que sí son miembros.

### Marcadores borrados

Dos individuales de D1 · Grupo 1 (A vs. C) tienen games imposibles en
Stadium (249-251, 67-69, 50-52). El ganador es correcto y cuenta para el
rating; solo se dejó el marcador en blanco:

- Montijo Rivera, Jerall def. Cuadro Perez, Ryan
- Birriel Rivera, Oscar def. Aviles Perez, Chrisnomar

---

## 4. Verificación

El archivo se pasó por el importador oficial del sitio (el de
`index.html`, con el arnés de `tests/harness`) usando jugadores de prueba:
320 partidos leídos, 0 omitidos, 0 marcados como retiro, con la categoría,
fase, grupo y ronda correctos en cada uno. Eso comprueba el **formato**, no
los ratings: los puntos reales los calcula el sitio con los ratings de la
base de datos cuando se procesa.
