# Lares Open 2026 — Inscripciones individuales

Guía operativa del 6to Lares Open de Tenis de Mesa en el portal de
inscripciones.

**Torneo:** sábado 26 y domingo 27 de septiembre de 2026
**Sede:** Coliseo Félix "Amiguito" Méndez Acevedo, Lares · 16 mesas
**Organizan:** FPTM y Club Tenis de Mesa Patriotas de Lares
**Formato:** individual por categorías · grupos de 3 y todos pasan a
eliminación sencilla

---

## 1. Lo primero: esto no toca la Copa Olímpica

Los dos torneos conviven en la misma página. Arriba de Inscripciones hay un
selector con un chip por torneo, y de ahí sale todo lo que se ve debajo.

|  | Copa Olímpica 2026 | Lares Open 2026 |
|---|---|---|
| Datos | `insc_equipos` | `insc_registro` |
| Nombre en el código | `COPA_TORNEO` | `TORNEO_ACTIVO` |
| Abrir / cerrar | `inscripciones_open` | `inscripciones_open_lares` |
| Prórroga | `insc_ignorar_deadline` | `insc_ignorar_deadline_lares` |
| Archivar | `torneo_archivado` | `torneo_archivado_lares` |
| Panel de admin | Gestionar Equipos | Gestionar Inscritos, Exportar, Reportes, Logística |

La Copa se quedó con **las claves de siempre** en `app_settings`: lo que ya
estaba guardado de ella sigue mandando exactamente igual. El Lares Open
estrena claves nuevas, que no existían antes. Por eso abrir, cerrar, extender
o archivar uno **no cambia nada del otro**.

No hay SQL que correr: `insc_registro` y `app_settings` ya existen, y las
claves nuevas se crean solas la primera vez que se pulsa el botón.

---

## 2. Abrir las inscripciones

En el panel de admin, sección **🏓 Torneo & Inscripciones**:

1. En la tarjeta **Inscripciones** escoge el chip **Lares Open** (la tarjeta
   dice a qué torneo se refiere: *"Inscripciones · Lares Open 2026"*).
2. Clic en la tarjeta hasta que diga **"Abiertas — clic para cerrar"**.

Eso es todo. Mientras estén cerradas, el admin sigue viendo el formulario con
el aviso *"Vista previa"* para poder probarlo sin que entre nadie más.

> El mismo chip manda en **Archivar Torneo**. Si vas a archivar la Copa
> cuando termine, selecciona su chip primero — la descripción de la tarjeta
> te dice qué torneo vas a archivar.

---

## 3. Las reglas que están programadas

| Regla | Cómo funciona |
|---|---|
| **Máx. 2 categorías por día** | La tercera del mismo día se rechaza al seleccionarla. |
| **Sin coincidir en horario** | Dos categorías a la misma hora no se pueden escoger juntas. |
| **Política de ascenso** | Para subir de categoría hay que estar inscrito en la natural. El sistema la exige y la ofrece. Si las dos caen a la misma hora la regla no aplica, porque sería imposible cumplirla. |
| **Edad por año natural** | Al 31 de diciembre de 2026, como dice el reglamento. |
| **Cuota de no miembro** | $10.00 de cargo base a quien no sea miembro activo; $0 al miembro. |
| **Precio** | $20.00 por categoría; $11.00 la de 7 años o menos. |
| **Multas por no arbitrar** | Se cobran una sola vez, en la primera inscripción del torneo (`INSC_MULTAS`). |
| **Créditos** | Un crédito aprobado de una cancelación anterior se aplica solo al total. |

### Ascenso, con un ejemplo real del itinerario

Un jugador de 1450 que quiera jugar **Rating 1600** (domingo 9:00 a.m.) tiene
que inscribirse también en **Rating 1500** (sábado 9:00 a.m.), que es su
categoría natural. El formulario se lo dice con el candado y el texto
*"Requiere: 1500 o Menos"*.

En cambio **1900** y **1500** caen los dos el sábado a las 9:00 a.m.: ahí no
se exige nada, porque no se pueden jugar ambas.

---

## 4. Dos cosas que hay que terminar a mano

### El arte del torneo

El banner busca **`Logo_Lares_Open_2026.png`** en la raíz del repositorio. Si
no está, prueba con `.svg` y, si tampoco, enseña el nombre en tipografía —
que es lo que se ve ahora mismo. Para que salga el arte oficial basta con
dejar el archivo ahí con ese nombre exacto; no hay que tocar código.

El escudo del Club Patriotas de Lares (`Logo_Patriotas_Lares.png`, sacado del
reglamento oficial) sí está y se muestra junto a la línea de organizadores.

### La fecha límite

El reglamento dice que "será anunciada próximamente". Mientras tanto, el
código usa una tentativa: **jueves 24 de septiembre, 10:00 p.m. AST**
(`INSC_DEADLINE` en `index.html`). Dos formas de ajustarla:

- **Sin tocar código:** pasada esa hora, el botón **"Extender: abrir igual"**
  de la tarjeta de Inscripciones mantiene abiertas las del Lares Open (y solo
  las suyas).
- **Definitiva:** cambiar `INSC_DEADLINE` cuando la federación anuncie la
  oficial.

---

## 5. Export a Stadium Compete

El evento del Lares Open todavía **no existe en Stadium**, así que las
categorías no llevan `stadiumId` verificado y el export avisa que las omite
en vez de generar un CSV que Stadium rechazaría.

Cuando se cree el torneo en Stadium: copiar de *Admin → Edit Event Settings*
el nombre de cada evento y añadir a cada categoría de `INSC_CATEGORIES`
`stadiumId: '<slug>'` y `stadiumVerified: true`. Lares tampoco está en
`STADIUM_CLUB_IDS`; si hace falta el club, se añade ahí su UUID.

Como el torneo es de un solo fin de semana, el modal de export no enseña los
botones "Parte 1 / Parte 2" ni el de dobles: va todo en un archivo.

---

## 6. Categorías cargadas

| # | Categoría | Día | Hora | Costo | Premiación |
|---|---|---|---|---|---|
| 1 | Rating 1900 o menos | Sáb 26 | 9:00 a.m. | $20 | $80 · $70 · $60 (x2) |
| 2 | Rating 1500 o menos | Sáb 26 | 9:00 a.m. | $20 | $50 · $40 · $30 (x2) |
| 3 | Rating 1700 o menos | Sáb 26 | 12:00 p.m. | $20 | $60 · $50 · $40 (x2) |
| 4 | 15 o menos Femenino | Sáb 26 | 2:00 p.m. | $20 | $40 · $35 · $30 (x2) |
| 5 | 15 o menos Masculino | Sáb 26 | 2:00 p.m. | $20 | $40 · $35 · $30 (x2) |
| 6 | 11 o menos Femenino | Sáb 26 | 2:00 p.m. | $20 | $30 · $25 · $20 (x2) |
| 7 | 11 o menos Masculino | Sáb 26 | 2:00 p.m. | $20 | $30 · $25 · $20 (x2) |
| 8 | Rating 1600 o menos | Dom 27 | 9:00 a.m. | $20 | $55 · $45 · $35 (x2) |
| 9 | Rating 1800 o menos | Dom 27 | 9:00 a.m. | $20 | $70 · $60 · $50 (x2) |
| 10 | Seniors 40 años o más (Mixto) | Dom 27 | 12:00 p.m. | $20 | $35 · $25 · $20 (x2) |
| 11 | 7 o menos Abierto | Dom 27 | 12:00 p.m. | $11 | Trofeo 1°-4° · Medalla 5°-8° |
| 12 | 9 o menos Femenino | Dom 27 | 12:00 p.m. | $20 | Trofeo 1°-4° · Medalla 5°-8° |
| 13 | 9 o menos Masculino | Dom 27 | 12:00 p.m. | $20 | Trofeo 1°-4° · Medalla 5°-8° |
| 14 | 13 o menos Femenino | Dom 27 | 2:00 p.m. | $20 | $35 · $30 · $25 (x2) |
| 15 | 13 o menos Masculino | Dom 27 | 2:00 p.m. | $20 | $35 · $30 · $25 (x2) |

No se juegan partidos por el 3er y 4to lugar: se premian **dos terceros
lugares** en todas las categorías.
