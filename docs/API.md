# API pública FPTM — para la página web oficial

Documento para el desarrollo de la página oficial de la federación. Describe
cómo leer atletas, ratings, membresías, clubes y torneos desde la plataforma
`ratings.ttmpr.xyz`.

**Antes de usar esto:** hay que correr `sql/create_api_publica.sql` una vez en
Supabase → SQL Editor. Ese script crea las tres vistas que se documentan aquí.

---

## 1. Conexión

La plataforma corre sobre Supabase, que expone una API REST automática
(PostgREST). No hay que instalar nada — son llamadas HTTP normales.

```
Base URL:  https://qrvyfdpwtearfpjruwja.supabase.co/rest/v1/
```

Toda petición lleva dos cabeceras con la llave publicable:

```
apikey:        <LLAVE_PUBLICABLE>
Authorization: Bearer <LLAVE_PUBLICABLE>
```

La llave publicable se entrega aparte. Es de solo lectura sobre estas vistas y
está pensada para ir en el JavaScript del sitio — es visible para cualquiera
que mire el código fuente, y está bien que así sea. **No es** la llave de
servicio; esa nunca sale del panel de administración.

CORS está habilitado para cualquier origen, así que se puede llamar
directamente desde el navegador en `fptm.webisla.site` o en el dominio final.

---

## 2. `api_jugadores` — atletas, ratings y membresías

```
GET /rest/v1/api_jugadores?select=*&order=rating.desc.nullslast
```

| Campo | Tipo | Descripción |
|---|---|---|
| `member_id` | int | **ID único del atleta.** Estable, es la llave para todo |
| `nombre` | text | Nombre |
| `apellido` | text | Apellido |
| `nombre_completo` | text | Nombre y apellido ya concatenados |
| `sexo` | text | `M` o `F` |
| `club` | text | Club al que pertenece (`null` si no tiene) |
| `escuela` | text | Escuela, cuando aplica |
| `rating` | int | **Rating vigente.** Es el que se muestra |
| `rating_inicio` | int | Rating antes del último torneo procesado |
| `anio_nacimiento` | int | Año de nacimiento |
| `edad` | int | Edad cumplida, calculada al momento de la consulta |
| `membresia_activa` | bool | `true` si la membresía está vigente hoy |
| `membresia_vence` | date | Fecha de vencimiento (`YYYY-MM-DD`) |
| `foto_url` | text | Foto aprobada del atleta, o `null` |
| `es_menor` | bool | `true` si la foto corresponde a un menor de edad |

### Sobre `rating` vs `rating_inicio`

Internamente hay dos columnas: el rating de inicio y el rating nuevo que
escribe el sistema cuando se procesa un torneo. `rating` ya resuelve eso — es
el nuevo si existe, y el inicial si el atleta todavía no ha competido. Para
mostrar en la web, usar siempre `rating`. `rating_inicio` sirve si se quiere
mostrar el movimiento (`rating - rating_inicio`).

### Sobre fecha de nacimiento

Se expone el **año** y la **edad**, no la fecha completa. Con eso se arman las
categorías por edad (Sub-11, Sub-15, etc.) sin publicar un dato identificativo
de menores en una web abierta. Si en algún momento hace falta la fecha exacta
para algo puntual, se resuelve con un endpoint autenticado aparte.

### Sobre `foto_url` y `es_menor`

Solo aparecen fotos que pasaron por aprobación administrativa. Cuando
`es_menor` es `true`, la foto se subió con autorización del tutor legal
registrada. Aun así, queda a criterio del sitio si publica fotos de menores en
un directorio abierto — el campo está ahí para poder decidirlo.

### Ejemplos

```bash
# Top 50 del ranking general
GET /api_jugadores?select=member_id,nombre_completo,club,rating
   &order=rating.desc.nullslast&limit=50

# Ranking femenino
GET /api_jugadores?sexo=eq.F&order=rating.desc.nullslast&limit=50

# Solo miembros activos
GET /api_jugadores?membresia_activa=is.true&order=rating.desc.nullslast

# Sub-15 (categoría por edad)
GET /api_jugadores?edad=lt.15&order=rating.desc.nullslast

# Un atleta específico
GET /api_jugadores?member_id=eq.1234

# Todos los de un club
GET /api_jugadores?club=eq.Bayam%C3%B3n%20TTC&order=rating.desc.nullslast

# Búsqueda por nombre (insensible a mayúsculas)
GET /api_jugadores?nombre_completo=ilike.*rivera*&limit=20
```

---

## 3. `api_clubes` — directorio de clubes

```
GET /rest/v1/api_clubes?select=*&order=club.asc
```

| Campo | Tipo | Descripción |
|---|---|---|
| `club` | text | Nombre del club (es la llave; empata con `api_jugadores.club`) |
| `logo_url` | text | Logo del club |
| `descripcion` | text | Descripción |
| `direccion` | text | Dirección física |
| `telefono` | text | Teléfono de contacto |
| `encargado` | text | Persona encargada |
| `total_jugadores` | int | Cantidad de atletas registrados en ese club |

---

## 4. `api_torneos` — torneos publicados

```
GET /rest/v1/api_torneos?select=*&order=fecha.desc
```

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | int | ID del torneo |
| `nombre` | text | Nombre del torneo |
| `fecha` | date | Fecha del evento |

Solo aparecen los torneos publicados. Los que están en borrador o borrados no
salen, así que se puede listar todo sin filtrar.

**Torneo activo:** es el primero al ordenar por `fecha.desc`.

```bash
GET /api_torneos?select=*&order=fecha.desc&limit=1
```

### Estado de inscripciones

Para saber si el botón de "Inscripciones" debe estar activo:

```bash
GET /rest/v1/app_settings?key=eq.inscripciones_open&select=value
```

Devuelve `[{"value":"true"}]` o `[{"value":"false"}]` (es texto, no booleano).
Si el arreglo viene vacío, tratarlo como cerrado.

Cuando esté abierto, el botón redirige a `https://ratings.ttmpr.xyz` — el
proceso de inscripción y de membresías se mantiene allí por ahora.

---

## 5. Sintaxis de consulta

La API es PostgREST, así que todo se hace por query string:

| Qué | Cómo |
|---|---|
| Escoger columnas | `?select=member_id,nombre_completo,rating` |
| Igual a | `?club=eq.Ponce%20TTC` |
| Distinto de | `?club=neq.Ponce%20TTC` |
| Mayor / menor | `?rating=gte.1500` · `?edad=lt.15` |
| Booleano | `?membresia_activa=is.true` |
| Nulo | `?club=is.null` |
| Contiene texto | `?nombre_completo=ilike.*rivera*` |
| Lista | `?member_id=in.(101,102,103)` |
| Ordenar | `?order=rating.desc.nullslast` |
| Paginar | `?limit=50&offset=100` |
| O lógico | `?or=(sexo.eq.F,edad.lt.15)` |

**Paginación:** el servidor devuelve como máximo 1000 filas por petición. Si el
listado completo de atletas pasa de ahí, hay que paginar con `limit`/`offset`.
Para saber el total sin traer todo:

```
GET /api_jugadores?select=member_id&limit=1
Header: Prefer: count=exact
→ la respuesta trae Content-Range: 0-0/847
```

### Ejemplo completo en JavaScript

```js
const API  = 'https://qrvyfdpwtearfpjruwja.supabase.co/rest/v1';
const KEY  = '...';  // llave publicable
const HEAD = { apikey: KEY, Authorization: `Bearer ${KEY}` };

async function topRanking(limite = 50) {
  const url = `${API}/api_jugadores`
    + `?select=member_id,nombre_completo,club,rating,foto_url`
    + `&order=rating.desc.nullslast&limit=${limite}`;
  const res = await fetch(url, { headers: HEAD });
  if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`);
  return res.json();
}
```

---

## 6. Cuándo se actualizan los datos

No hay un horario fijo; los datos cambian cuando el administrador ejecuta cada
proceso desde el panel de `ratings.ttmpr.xyz`:

| Dato | Se actualiza cuando |
|---|---|
| `rating` | Se sube y procesa un torneo. El sistema recalcula y escribe el rating nuevo de cada participante |
| `membresia_activa` / `membresia_vence` | Se aprueba una membresía nueva o una renovación. Además `membresia_activa` se recalcula sola cada día, porque se compara contra la fecha actual |
| `club` | Se aprueba una solicitud de cambio de club |
| `foto_url` | Se aprueba una foto |
| `api_torneos` | Se publica un torneo |

En la práctica los ratings se mueven después de cada torneo — cada dos o tres
semanas en temporada. **No hay webhooks todavía**, así que la página web debe
consultar la API en cada carga (o cachear unos minutos). No conviene cachear
por días: quedaría mostrando ratings viejos después de un torneo.

---

## 7. Notas de seguridad

Estas vistas son de **solo lectura**. La llave publicable no permite escribir,
modificar ni borrar nada.

Lo que las vistas deliberadamente **no** exponen:

- Correos electrónicos
- Direcciones postales
- Fecha de nacimiento completa (solo año y edad)
- Solicitudes de membresía, inscripciones y pagos
- Cualquier dato de contacto de menores

Si el sitio necesita algún dato que no está en la lista de arriba, pedirlo
antes de buscar una vía alterna — se evalúa y se añade a la vista si procede.
Hay otras tablas visibles en la base de datos que no están documentadas aquí;
no son parte del contrato y pueden cambiar o cerrarse sin aviso. **Usar
únicamente `api_jugadores`, `api_clubes`, `api_torneos` y `app_settings`.**

---

## 8. Pendientes conocidos

- **Cerrar el acceso directo a la tabla base.** Hoy `Base de Datos` sigue
  siendo legible con la llave publicable, incluyendo columnas sensibles. El
  paso siguiente es migrar `ratings.ttmpr.xyz` a estas mismas vistas y luego
  restringir la tabla. Hasta que eso pase, la protección real de las columnas
  sensibles depende de que nadie consulte la tabla directamente.
- **Webhooks / notificación de cambios.** Por ahora la web consulta y ya.
- **Endpoint de resultados por torneo.** Los partidos y resultados existen en
  la base de datos pero no están expuestos como vista pública. Se puede añadir
  si la web los va a mostrar.
