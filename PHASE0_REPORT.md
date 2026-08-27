# Informe de Fase 0

Plan de migración a Kileaaa · red de seguridad previa a cualquier cambio.

**Alcance ejecutado:** sólo Fase 0.
**No se ha hecho:** Fase 1, Developer Mode, Tournament Manager, cambios en
Supabase, migraciones, despliegues, ni ninguna modificación del algoritmo
oficial de rating ni de su comportamiento en producción.
**No se ha consultado** ninguna implementación de rating del repositorio
antiguo `kileaaa.com`.

`ratings.ttmpr.xyz` es la única autoridad de rating. `index.html` **no se ha
modificado**.

---

## 1. Ficheros creados o modificados

### Creados

| Fichero | Qué es |
|---|---|
| `tests/harness/extract.mjs` | Extrae declaraciones de nivel superior de `index.html` por nombre |
| `tests/harness/sandbox.mjs` | Ejecuta el pipeline oficial en `vm` con DOM y red simulados |
| `tests/harness/fixtures.mjs` | Carga los datos históricos oficiales del repositorio |
| `tests/harness/generate-golden.mjs` | Regenera los ficheros golden del replay |
| `tests/rating-core.test.mjs` | Objetivos B1–B5 |
| `tests/rating-batch.test.mjs` | Objetivos B6–B8 |
| `tests/importer.test.mjs` | Objetivos B9–B15 |
| `tests/replay.test.mjs` | Objetivo C |
| `tests/golden/*.json` | Cinco fotos de comportamiento sobre datos históricos |
| `tests/README.md` | Cómo correr e interpretar los tests |
| `SECURITY_FINDINGS.md` | Objetivo D — diez hallazgos, sin corregir |
| `docs/PHASE0_BACKUP_AND_STAGING.md` | Objetivo A — backup, restauración y staging |
| `PHASE0_REPORT.md` | Este documento |

### Modificados

**Ninguno.** En particular, `index.html` está intacto: los tests extraen su
código en vez de copiarlo o alterarlo.

### No creados a propósito

No se añadió `package.json`. Los tests usan sólo módulos incorporados de Node
(`node:test`, `node:assert`, `node:vm`), así que no hace falta, y un
`package.json` en la raíz de un sitio estático es un cambio con efectos que
no tocaba asumir en Fase 0.

---

## 2. Tests añadidos

117 tests en 22 suites.

| Objetivo | Cobertura | Tests |
|---|---|---|
| B1 | Fronteras de `POINT_TABLE` (los 7 tramos, por ambos lados) | 17 |
| B2 | Ratings iguales, simetría, desempate `rA >= rB` | 3 |
| B3 | Victoria del favorito en los 7 tramos | 8 |
| B4 | Victoria del underdog, monotonía | 8 |
| B5 | Suma cero en ~5.000 combinaciones, signos, enteros | 3 |
| B6 | Rating congelado al inicio; el orden no altera el neto | 3 |
| B7 | Varios partidos por jugador, ganados/perdidos, suma cero por torneo | 4 |
| B8 | Una sola actualización por jugador, columna `New Rating`, orden de escritura | 5 |
| B9 | Fusión multi-archivo y por qué subir por separado no es equivalente | 3 |
| B10 | Retirados: cero cambio, `notas`, no cuenta como victoria ni derrota | 5 |
| B11 | W/O y "Default" | 2 |
| B12 | Exclusión de dobles por nombre y por `stadiumId` | 4 |
| B13 | `idFptm` en ambos órdenes de proveedor, variantes y rechazos | 5 |
| B14 | Filas omitidas, jugador desconocido, CSV vacío, encabezado no descartado | 6 |
| B15 | Vista previa sin escribir, desglose por categoría, botón de aplicar | 5 |
| C | Replay de 5 conjuntos históricos + consistencia entre conjuntos | 36 |

### Qué ejercitan exactamente

No son una reimplementación. El arnés extrae de `index.html` y ejecuta las
funciones reales:

```
INSC_CATEGORIES  POINT_TABLE  getPoints  idFptm  catDesdeEvento
esCategoriaDobles  faseYRonda  subirLoadTexto  subirProcesarCsv
subirApplyRatings
```

La capa de red está interceptada: `sbPost`, `sbPatch` y `sbGet` **registran**
lo que se escribiría en `partidos`, `resultados_evento` y `Base de Datos` en
vez de escribirlo. No hay peticiones. No hay credenciales. Supabase no se
toca ni en lectura.

---

## 3. Resultados exactos

```
$ node --test tests/*.test.mjs

# tests 117
# suites 22
# pass 117
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 2032.508634
```

| Fichero | Tests | Pasan | Fallan |
|---|---|---|---|
| `rating-core.test.mjs` | 39 | 39 | 0 |
| `rating-batch.test.mjs` | 12 | 12 | 0 |
| `importer.test.mjs` | 30 | 30 | 0 |
| `replay.test.mjs` | 36 | 36 | 0 |

Durante el desarrollo fallaron cuatro tests. Ninguno era un defecto de
producción: tres eran del arnés (los `const` no cruzan entre scripts de `vm`;
los objetos creados dentro del `vm` tienen otro prototipo y `deepEqual`
estricto los rechaza; `subirApplyRatings` mutaba el array de jugadores del
test y contaminaba la prueba siguiente) y el cuarto era un supuesto mío
equivocado sobre los datos — ver el hallazgo del rating 0 en la sección 5.

---

## 4. Torneos históricos reproducidos

Ratings de partida: `restore_rating_backup.sql`, el snapshot oficial de 537
jugadores previo al Albergue Olímpico 2026.

| Conjunto | Fuente | Formato | Filas | Partidos | Participantes | Suma neta |
|---|---|---|---|---|---|---|
| `albergue-2026-stadium` | `TODOS -Albuergue.Olimpico.2026.csv` | Stadium Compete | 433 | 374 | 151 | 0 |
| `albergue-2026-simple` | `albergue_olimpico_2026.csv` | simple | 391 | 333 | 148 | 0 |
| `albergue-2026-carga-sql` | `carga_albergue_2026.sql` | lista del cargador | 376 | 323 | 151 | 0 |
| `open-2026-carga-sql` | `carga_open_2026.sql` | lista del cargador | 411 | 358 | 151 | 0 |
| `1700-under-carga-sql` | `carga_1700_under.sql` | lista del cargador | 73 | 73 | 41 | 0 |

Cinco conjuntos, por encima del mínimo de tres. `1700-under` es el más limpio:
cobertura del 100 %, ningún partido descartado.

Cada conjunto verifica además, en cada corrida:
- suma cero del torneo completo,
- una y sólo una actualización de rating por participante,
- `rating_fin = rating_inicio + suma de deltas`,
- el rating de partida coincide con el snapshot oficial.

---

## 5. Discrepancias encontradas

### D-1 · Los tres artefactos del Albergue 2026 no describen el mismo torneo

El repositorio guarda tres ficheros del mismo evento y **no coinciden**:

| | Filas parseadas |
|---|---|
| `TODOS -Albuergue.Olimpico.2026.csv` | 433 |
| `albergue_olimpico_2026.csv` | 391 |
| `carga_albergue_2026.sql` | 376 |

Entre los dos últimos hay 358 partidos comunes, 17 sólo en uno y 18 sólo en
el otro. Los deltas por jugador coinciden en 80 de 151; difieren en 71.

Es coherente con que sean **revisiones distintas de la misma carga**: el
repositorio también contiene `carga_albergue_2026rev.sql` y un CSV `rev`.

**Consecuencia:** no pueden validarse entre sí, y sin las filas reales de
`partidos` en Supabase no hay forma de decidir cuál corresponde a producción.
Cada conjunto sirve sólo como golden de sí mismo. No se han inventado valores
esperados.

### D-2 · Tres jugadores con `Rating = 0` en el snapshot oficial

Member ID `49446`, `63225`, `81819`. Dato real del histórico, no un error del
test.

Efecto: un rating 0 deja la diferencia por encima de 250 frente a cualquier
jugador con rating, así que el favorito **gana 0 puntos si vence** y pierde 32
si no. En la práctica, ganarle a un jugador con rating 0 no puntúa, y perder
contra él cuesta el máximo.

Queda fijado en un test para que sea visible. No se ha corregido ningún dato.

### D-3 · Cobertura incompleta del snapshot

El snapshot tiene 537 jugadores, pero los partidos históricos mencionan
identificadores que no están en él:

| Conjunto | Descartados | IDs fuera del snapshot |
|---|---|---|
| `albergue-2026-stadium` | 59 | 17 |
| `albergue-2026-simple` | 58 | 19 |
| `albergue-2026-carga-sql` | 53 | 17 |
| `open-2026-carga-sql` | 53 | 17 |
| `1700-under-carga-sql` | 0 | 0 |

El pipeline los descarta correctamente y avisa. No es un fallo, pero significa
que los golden reflejan un subconjunto, no el torneo entero.

### D-4 · Tres CSV históricos que el importador actual no puede leer

`torneo_1700_under.csv`, `albergue_olimpico_march2026.csv` y
`albergue.olimpico.2026rev` usan un formato `Round,WinnerID,LoserID,Scores`
que el importador **no reconoce**: no tiene las columnas
`winnerMembershipIds`/`loserMembershipIds` que activan la rama Stadium, así
que cae a la rama simple y parsea `pA = "Group 10 (B vs. C)"`,
`pB = "fprtm|71953"`. Basura silenciosa — no falla, produce filas inválidas
que luego se descartan por jugador desconocido.

Se cargaron en su día con los scripts de Python del repositorio
(`upload_torneo.py` y compañía), no por la interfaz.

**Riesgo real:** si alguien sube hoy uno de esos ficheros por la web, verá
"partidos detectados" y un aviso de jugadores no encontrados, sin que nada
indique que el formato es incorrecto.

### D-5 · Hueco documentado: no hay salidas de producción en el repositorio

Las filas reales de `partidos` y `resultados_evento` viven en Supabase. La
Fase 0 no toca producción, así que **no ha sido posible comparar contra los
valores oficialmente registrados**. Los golden son fotos generadas por el
propio pipeline sobre entradas históricas reales, no salidas de producción.

Cierre propuesto para la Fase 1, una vez exista staging: restaurar un backup
en staging y comparar el replay contra las filas reales de `partidos` y
`resultados_evento`. Eso convertiría los golden en una verificación de
extremo a extremo. Mientras tanto, siguen siendo un detector de cambios
válido.

---

## 6. Comportamiento inusual preservado a propósito

Todo lo siguiente está fijado por tests marcados `CARACTERÍSTICA PRESERVADA`.
**No debe "arreglarse" sin una decisión explícita.**

### 6.1 · W/O no puntúa para nadie

El importador usa un único patrón, `/retired|retir|walkover|w\/o/i`, así que
**W/O y walkover se tratan exactamente igual que un retirado**: ni el ganador
gana puntos ni el ausente los pierde.

El PRD (`docs/PRD.md` §7.6) describe lo contrario:

> *"Default / W/O result: winner gains points; defaulting player loses points
> (treated as a regular loss)."*

**El código y el PRD no coinciden.** El código es el que está en producción y
es el que se ha fijado. Alinear uno con otro es una decisión de la federación,
no una corrección técnica.

### 6.2 · "Default" sí puntúa

El mismo patrón **no** incluye `default`. Un partido descrito como "Default"
se califica como un partido normal, con intercambio completo de puntos. Junto
con 6.1, esto significa que dos palabras que el PRD trata como sinónimas se
comportan de forma opuesta.

### 6.3 · `partidos.rating_*_despues` es por partido, no acumulado

Se guarda como `rating de llegada + delta de ESE partido`. Para un jugador con
tres partidos, las tres filas parten del mismo rating inicial, así que
**ninguna refleja su rating real después de ese partido** en el orden del
torneo, ni su rating final.

Es consistente con la regla oficial del rating congelado, pero se lee con
facilidad como un histórico cronológico y no lo es. El rating final está en
`resultados_evento.rating_fin`.

### 6.4 · El encabezado `pA,pB,win` no se descarta

El filtro de encabezado de la rama simple busca
`/jugador|player|ganador|winner/i`. La cadena `pA,pB,win` no coincide, así que
la primera línea se parsea como si fuera un partido y acaba contada como
jugador desconocido.

Afecta a `albergue_olimpico_2026.csv`, que usa exactamente ese encabezado. El
efecto es inofensivo — un aviso de más — pero es real y está fijado.

### 6.5 · Con ratings iguales, A es el favorito

`aIsFav = rA >= rB`. En el tramo 0–24 no tiene efecto observable, porque
favorito y underdog valen ambos 8 puntos. La rama existe y queda documentada
por si algún día cambia la tabla.

---

## 7. Backup y restauración — hallazgos

Detalle completo en `docs/PHASE0_BACKUP_AND_STAGING.md`.

**Lo que funciona bien.** 17 tablas exportadas semanalmente (lunes 03:00 PR) a
un bucket privado, en JSON y CSV, con resumen de conteos. La restauración es
idempotente y maneja bien los casos especiales (`Member ID` como PK,
`audit_log` sin `id`). La decisión de no publicar los exports en un
repositorio público está bien razonada.

**Huecos encontrados.**

| # | Hueco |
|---|---|
| 1 | **Storage no se respalda**: `club-logos` y `player-photos` se perderían |
| 2 | **`auth.users` no se respalda**: una restauración deja datos, no accesos |
| 3 | **No hay volcado de esquema**: se reconstruye a mano con ~30 `.sql` sin orden |
| 4 | **`insc_equipos`, `insc_divisiones` e `insc_busca_companero` no están en la lista de tablas**: el módulo Copa Olímpica queda fuera del backup |
| 5 | **Los backups viven en el mismo proyecto** que protegen (punto único de fallo) |
| 6 | **Sin retención ni monitorización**: nadie se entera si el workflow falla |
| 7 | **El ejercicio de restauración no consta como realizado** |

El hueco 4 es el más urgente de los que se pueden cerrar sin decisiones de
arquitectura: son tres tablas con dinero asociado y basta añadirlas a la lista
`TABLES` de `backup/export_backup.mjs`. **No se ha hecho** — es un cambio de
código y la Fase 0 no modifica nada.

El hueco 3 es el que bloquea el staging: `Base de Datos`, `torneos`,
`partidos` y `resultados_evento` **no tienen fichero de creación en el
repositorio**. Existen sólo en producción. Hay que extraer su DDL antes de
poder levantar un proyecto desde cero.

---

## 8. Arquitectura de staging recomendada

Pasos exactos en `docs/PHASE0_BACKUP_AND_STAGING.md`. Resumen:

**Principio:** producción y staging nunca comparten datos escribibles.
Proyectos Supabase distintos, credenciales distintas, flujo en una sola
dirección (producción → staging), y ninguna credencial cruzada.

**Orden de trabajo propuesto**

1. Extraer la DDL de las cuatro tablas que no están en el repositorio y
   guardarla como `sql/schema_core.sql`. *Bloquea todo lo demás.*
2. Fijar y verificar el orden de ejecución del esquema (17 pasos propuestos).
3. Crear el proyecto `kileaaa-staging`, misma región, plan Free.
4. Escribir el script de anonimización (export → transformar → restaurar).
5. Restaurar en staging. Esto **cierra a la vez** el ejercicio de restauración
   pendiente desde hace tiempo.
6. Verificar conteos contra `_resumen.txt`.

**Qué se copia y qué no.** Los cálculos de rating no dependen de ningún dato
personal, así que se puede anonimizar sin perder fidelidad:

- *Tal cual*: `torneos`, `partidos`, `resultados_evento`, ratings, sexo, club,
  configuración y contenido público.
- *Anonimizado*: nombres, correos (`@staging.invalid`), direcciones (vaciar),
  fechas de nacimiento (**conservar sólo el año**: las reglas de categoría
  dependen del año, no del día).
- *Omitido*: `player_reg_tokens` (serían credenciales vivas), `audit_log`
  (su JSON contiene los datos personales sin anonimizar y sortearía todo lo
  anterior), fotografías de personas, cuentas de `auth.users`, y cualquier
  referencia de pago.

---

## 9. Resumen de seguridad

Diez hallazgos en `SECURITY_FINDINGS.md`, **ninguno corregido**.

| # | Severidad | Hallazgo |
|---|---|---|
| F-01 | **Crítica** | `isAdmin()` devuelve `true` para cualquier sesión iniciada |
| F-02 | Alta | La llave publicable lee email, dirección y fecha de nacimiento de `Base de Datos` |
| F-03 | Alta | El navegador escribe ratings y partidos directamente, sin transacción |
| F-04 | Alta | 18 políticas RLS con `TO authenticated USING(true) WITH CHECK(true)` |
| F-05 | Media | ~20 políticas con `joel@ttmpr.xyz` escrito a mano |
| F-06 | Media | La auditoría registra `anon` en las escrituras con la llave publicable |
| F-07 | Media | Los backups viven en el mismo proyecto Supabase |
| F-08 | Media | `app_settings` (interruptores de inscripción) escribible por cualquier autenticado |
| F-09 | Baja-Media | `service_role` en secretos de un repositorio público |
| F-10 | Baja | No existe staging: todo se prueba contra producción |

**Lo que hoy contiene el riesgo no es el código, es que sólo hay una cuenta.**
F-01 y F-04 sólo están acotados porque no existe un segundo usuario. En cuanto
se cree uno —un árbitro, un organizador, el admin de LAI— tendrá la interfaz
de administración completa y escritura sobre las tablas del F-04.

**Bloqueantes para Developer Mode:** F-01 (no hay frontera de privilegio),
F-06 (no hay atribución fiable), F-08 (el kill switch sería escribible por
cualquiera), F-10 (no hay entorno al que cambiar).

**Bloqueantes para multi-organización:** F-02 y F-04 (sin predicado de
pertenencia, un inquilino ve al otro), F-05 (no hay un correo que pueda ser
admin de todas).

---

## 10. Alcance propuesto para la Fase 1

Pendiente de aprobación. Nada de esto se ha empezado.

### 1.0 — Staging (bloquea todo lo demás)
- Extraer la DDL de `Base de Datos`, `torneos`, `partidos`,
  `resultados_evento` → `sql/schema_core.sql`.
- Verificar el orden de ejecución del esquema levantando el proyecto desde cero.
- Crear `kileaaa-staging`.
- Escribir el script de anonimización.
- Restaurar y verificar conteos. Cierra el ejercicio de restauración pendiente.

### 1.1 — Cerrar los huecos de backup
- Añadir `insc_equipos`, `insc_divisiones` e `insc_busca_companero` a la lista
  de tablas del exportador.
- Añadir un destino de backup fuera de Supabase.
- Aviso cuando el workflow semanal falle.

### 1.2 — Roles reales (F-01, F-05)
- Claim de rol en el JWT: `owner` / `admin` / `arbitro` / `jugador`.
- Reescribir `isAdmin()` para leer el claim.
- Migrar las ~20 políticas con correo literal al claim.
- Probar cada cambio en staging antes de producción.

### 1.3 — Endurecer la RLS (F-02, F-04, F-08)
- Retirar el SELECT de `anon` sobre `Base de Datos`; dejar las vistas `api_*`
  como único camino público. Revisar antes qué consultas de `index.html` leen
  columnas sensibles con la llave publicable.
- Sustituir las 18 políticas `USING(true)` por predicados de rol, **tabla por
  tabla**, verificando la interfaz tras cada una.
- Política propia para `app_settings`.

### 1.4 — Atribución (F-06)
- Que todas las escrituras privilegiadas viajen con el JWT de sesión.
- Considerar rechazar escrituras anónimas en las tablas auditadas.

### 1.5 — Developer Mode
Sólo cuando 1.0 y 1.2 estén hechos. Las cuatro capas del plan: entrada oculta
sin privilegio, identidad verificada por la base, capacidades (cambio de
entorno, vista previa de rol y de organización sin escritura, banderas,
diagnósticos), y salvaguardas (banner, auditoría con correo real, kill switch,
prohibición de ampliar políticas).

### Fuera de alcance en la Fase 1
Tournament Manager, tenencia multi-organización (Fase 2), y **cualquier cambio
al algoritmo oficial de rating o a su comportamiento**. La corrección de
`subirApplyRatings` propuesta en F-03 mueve *dónde se ejecuta* el cálculo, no
*qué* calcula, y aun así conviene tratarla aparte y con los tests de esta
fase como red.

### Decisión pendiente que no bloquea la Fase 1

W/O (sección 6.1): el código y el PRD discrepan. Hace falta una decisión de la
federación sobre cuál es la regla correcta. **Hasta entonces el comportamiento
actual se conserva intacto**, y el test lo protege de cambios accidentales.

---

*Fin de la Fase 0. A la espera de revisión. Nada se ha comiteado.*
