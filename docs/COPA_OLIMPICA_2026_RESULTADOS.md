# Copa Olímpica 2026 — Resultados para el rating

Cómo se convirtieron los resultados por equipos de Stadium en partidos
individuales que el rating puede usar, y qué quedó fuera.

---

## 1. Qué subir y cómo

Archivo: **`copa_olimpica_2026_individuales.csv`** (361 partidos de sencillos).

En el sitio: **Subir resultados**

1. **Nombre del torneo:** `Copa Olímpica 2026`
2. **Fecha:** `2026-09-19` (primer día)
3. **Categoría:** vacía (el archivo trae la división de cada partido)
4. Subir el CSV → debe decir *"361 partidos detectados"* y 4 categorías:
   Division 3 (146), Division 2 (134), Division 1 (51),
   Division 3 - Consolación (30). **Sin partidos omitidos.**
5. **Procesar** → revisar la vista previa → Guardar borrador → Publicar.

Súbelo **una sola vez y completo**. El rating de cada partido se calcula
contra el rating con que el jugador llegó al torneo, así que no se puede
subir por partes.

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
  cortó la lista de games del CSV en ese orden. **En los 139, cada corte
  coincidió exacto con quién ganó cada game.**
- Los games ganados de los individuales suman el resultado del equipo en
  los 139 (ej. 3-1).

Cuatro partidos de la D2 salían sin alineación en la primera copia de la
página; el admin los copió aparte desde Stadium. Esa copia trae nombres pero
no Member ID, así que el ID se tomó de los otros partidos del mismo jugador
en la Copa: los 14 nombres aparecen con un solo ID y en el mismo equipo.

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
| Dobles (no cuentan para rating) | 135 |
| Individuales no jugados (0-0, el equipo ya había ganado 3) | 183 |
| Partidos de equipo por **default**: *Best friends* (equipo 49) vs. Las Bravas, Los Noris y Los Handymen, grupo 6 de la D3 | 3 partidos |
| Individual con retiro `(RET)` (era un dobles) | 1 |
| Tercer lugar de Consolación D3 (Puntos Largos SS vs. Ping y Pong): *Not Submitted*, no se jugó | 1 partido |

### Jugadores que Stadium tenía sin Member ID

Cuatro jugadores se crearon directamente en Stadium, sin el número de la
FPTM. El admin confirmó el de los cuatro con su perfil en el sitio, y sus
29 individuales están en el archivo principal:

| Jugador | Equipo | Member ID | Individuales |
|---|---|---|---|
| Pagan Diaz, Keilymar | Los Proceres (D3) | 40982 | 9 |
| Colon, Fernando | Los Proceres (D3) | 48067 | 9 |
| Arroyo, Victor | Los Arroyo (D3, Morovis) | 93424 | 6 |
| Arroyo Martinez, Kennuel | Los Arroyo (D3, Morovis) | 83000 | 5 |

### Member ID corregido

Stadium tenía a **Dereck Ramos Dipiní** (Los Caballitos, D3) con el número
69735. Su perfil en el sitio dice **98960**; sus 5 individuales van con
98960.

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
361 partidos leídos, 0 omitidos, 0 marcados como retiro, con la categoría,
fase, grupo y ronda correctos en cada uno. Eso comprueba el **formato**, no
los ratings: los puntos reales los calcula el sitio con los ratings de la
base de datos cuando se procesa.
