# Tests de caracterización — pipeline oficial de ratings

Fase 0 del plan de migración a Kileaaa.

## Qué son estos tests

Fijan el comportamiento **actual** del pipeline oficial de ratings de
`ratings.ttmpr.xyz`. No validan la matemática: comprueban que no cambie.

Un fallo significa **"el comportamiento oficial cambió"**, no *"el cálculo
está mal"*. Si el cambio es deliberado y está aprobado, se actualiza el test
a propósito y se deja constancia del motivo.

**Una suite en verde es un detector de cambios, nunca una prueba de
corrección.** No debe citarse como tal.

## Autoridad

`ratings.ttmpr.xyz` contiene la única implementación oficial del rating FPTM:
`POINT_TABLE` y `getPoints()` (`index.html:6771-6791`), aplicados en lote por
`subirApplyRatings()` (`index.html:7699`).

No se consulta, importa ni compara ninguna implementación de rating del
repositorio antiguo `kileaaa.com`.

## Cómo correrlos

```bash
node --test tests/*.test.mjs
```

Sin dependencias: sólo `node:test`, `node:assert` y `node:vm`. No hay
`package.json` ni `npm install`. Requiere Node 20 o superior.

## Cómo funcionan

`index.html` es un fichero único sin módulos, así que los tests **no** copian
el código: lo extraen.

- `harness/extract.mjs` — recorta declaraciones de nivel superior de
  `index.html` por nombre. Si alguien las renombra o mueve, falla ruidosamente.
- `harness/sandbox.mjs` — evalúa esas declaraciones en un contexto `vm` con un
  DOM mínimo de mentira y stubs de red que **registran** lo que se escribiría
  en `partidos`, `resultados_evento` y `Base de Datos` sin escribir nada.
- `harness/fixtures.mjs` — carga los datos históricos oficiales del repositorio.
- `harness/generate-golden.mjs` — regenera los ficheros golden del replay.

`index.html` nunca se modifica. No hay red. No se toca Supabase.

## Ficheros

| Fichero | Cubre |
|---|---|
| `rating-core.test.mjs` | Fronteras de `POINT_TABLE`, empate, favorito, underdog, suma cero |
| `rating-batch.test.mjs` | Rating congelado al inicio, varios partidos por jugador, una sola aplicación neta |
| `importer.test.mjs` | Fusión multi-archivo, retirados, W/O, dobles, parseo de IDs, filas omitidas, borrador |
| `replay.test.mjs` | Replay de cinco conjuntos históricos contra `golden/` |

## Ficheros golden

`golden/*.json` son fotos del comportamiento actual sobre datos históricos
reales, generadas por el propio pipeline oficial.

**No son salidas de producción.** Las filas reales de `partidos` y
`resultados_evento` viven en Supabase y no están en el repositorio, así que
no pueden usarse como esperado sin inventarlas. El hueco está documentado en
`PHASE0_REPORT.md`.

Para regenerarlos tras un cambio **aprobado**:

```bash
node tests/harness/generate-golden.mjs           # muestra el diff, no escribe
node tests/harness/generate-golden.mjs --write   # escribe
```

Revisa el diff a mano antes de escribir.

## Comportamiento marcado como CARACTERÍSTICA PRESERVADA

Varios tests documentan comportamiento que puede sorprender y que se
conserva **a propósito**. No deben "arreglarse" sin una decisión explícita
sobre el pipeline oficial. Están listados en `PHASE0_REPORT.md`, sección 6.
