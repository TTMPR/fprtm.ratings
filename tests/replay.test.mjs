/**
 * FPTM · Fase 0 — Replay histórico (objetivo C)
 *
 * Vuelve a pasar conjuntos históricos reales por el pipeline oficial de
 * index.html y compara el resultado con los ficheros golden de tests/golden/.
 *
 * QUÉ ES Y QUÉ NO ES ESTO
 * Los golden son una foto del comportamiento actual, generada por el propio
 * pipeline oficial. NO son salidas de producción: las filas reales de
 * `partidos` y `resultados_evento` viven en Supabase y no están en el
 * repositorio, así que no se pueden usar como esperado sin inventarlas.
 * El hueco está documentado en PHASE0_REPORT.md.
 *
 * Un fallo aquí significa "el comportamiento oficial cambió", no "el
 * cálculo está mal".
 *
 * Ratings de partida: restore_rating_backup.sql, el snapshot oficial previo
 * al Albergue Olímpico 2026. No se usa ninguna implementación del
 * repositorio antiguo kileaaa.com.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runBatch } from './harness/sandbox.mjs';
import { DATASETS, ratingsSnapshot, playersFromSnapshot, resumen } from './harness/fixtures.mjs';

const GOLDEN = path.resolve(path.dirname(fileURLToPath(import.meta.url)), 'golden');

const snapshot = ratingsSnapshot();
const players = playersFromSnapshot(snapshot);

describe('C0 · Snapshot oficial de ratings', () => {
  test('restore_rating_backup.sql se lee entero', () => {
    assert.equal(snapshot.size, 537);
  });

  test('todos los ratings son enteros y ninguno es negativo', () => {
    for (const [id, r] of snapshot) {
      assert.ok(Number.isInteger(r), `rating no entero para ${id}: ${r}`);
      assert.ok(r >= 0, `rating negativo para ${id}: ${r}`);
      assert.ok(r < 3000, `rating implausible para ${id}: ${r}`);
    }
  });

  test('CARACTERÍSTICA PRESERVADA · tres jugadores tienen Rating = 0 en el snapshot', () => {
    // Dato real del histórico oficial, no un fallo del test. Un rating 0
    // frente a cualquier jugador con rating deja la diferencia por encima de
    // 250, así que el favorito gana 0 puntos si vence y pierde 32 si no.
    // Se fija aquí para que el efecto sea visible y no una sorpresa.
    const ceros = [...snapshot].filter(([, r]) => r === 0).map(([id]) => id).sort((a, b) => a - b);
    assert.deepEqual(ceros, [49446, 63225, 81819]);
  });

  test('el rango del snapshot no ha cambiado', () => {
    const valores = [...snapshot.values()];
    assert.equal(Math.min(...valores), 0);
    assert.equal(Math.max(...valores), 2174);
  });
});

for (const ds of DATASETS) {
  describe(`C · ${ds.id} — ${ds.torneo}`, () => {
    const file = path.join(GOLDEN, `${ds.id}.json`);

    test('existe el fichero golden', () => {
      assert.ok(existsSync(file),
        `falta ${file}. Genéralo con: node tests/harness/generate-golden.mjs --write`);
    });

    test('el replay reproduce el golden exactamente', async () => {
      const esperado = JSON.parse(readFileSync(file, 'utf8'));
      const r = await runBatch({ players, csv: ds.csv(), nombre: ds.torneo, fecha: '2026-03-01' });
      const actual = resumen(r);

      // Primero los agregados: dan un diff legible antes del volcado completo.
      for (const k of ['partidosParseados', 'partidosCalculados', 'partidosGuardados',
                       'participantes', 'actualizacionesDeRating', 'retirados']) {
        assert.equal(actual[k], esperado[k], `${ds.id}: cambió ${k}`);
      }
      assert.deepEqual(actual.jugadores, esperado.jugadores,
        `${ds.id}: cambiaron los deltas por jugador`);
    });

    test('el torneo conserva la suma cero', async () => {
      const r = await runBatch({ players, csv: ds.csv(), nombre: ds.torneo, fecha: '2026-03-01' });
      const neto = r.resultados.reduce((s, x) => s + (x.rating_fin - x.rating_inicio), 0);
      assert.equal(neto, 0, `${ds.id}: el torneo creó o destruyó ${neto} puntos`);
    });

    test('cada participante recibe exactamente una actualización de rating', async () => {
      const r = await runBatch({ players, csv: ds.csv(), nombre: ds.torneo, fecha: '2026-03-01' });
      const filtros = r.ratingWrites.map(w => w.filter);
      assert.equal(filtros.length, new Set(filtros).size);
      assert.equal(r.ratingWrites.length, r.resultados.length);
    });

    test('rating_fin = rating_inicio + suma de los deltas del torneo', async () => {
      const r = await runBatch({ players, csv: ds.csv(), nombre: ds.torneo, fecha: '2026-03-01' });
      const delta = new Map();
      for (const p of r.pending) {
        delta.set(p.idA, (delta.get(p.idA) ?? 0) + p.aGain);
        delta.set(p.idB, (delta.get(p.idB) ?? 0) + p.bGain);
      }
      for (const x of r.resultados) {
        assert.equal(x.rating_fin, x.rating_inicio + (delta.get(x.id_jugador) ?? 0),
          `${ds.id}: descuadre en el jugador ${x.id_jugador}`);
      }
    });

    test('el rating de partida coincide con el snapshot oficial', async () => {
      const r = await runBatch({ players, csv: ds.csv(), nombre: ds.torneo, fecha: '2026-03-01' });
      for (const x of r.resultados) {
        assert.equal(x.rating_inicio, snapshot.get(x.id_jugador),
          `${ds.id}: el jugador ${x.id_jugador} no partió de su rating del snapshot`);
      }
    });
  });
}

describe('C · Consistencia entre conjuntos del mismo torneo', () => {
  // HUECO DOCUMENTADO — no es un fallo del pipeline.
  //
  // El repositorio guarda tres artefactos del Albergue Olímpico 2026 y NO
  // describen la misma lista de partidos:
  //
  //   TODOS -Albuergue.Olimpico.2026.csv   433 filas parseadas
  //   albergue_olimpico_2026.csv           391
  //   carga_albergue_2026.sql              376
  //
  // Entre los dos últimos hay 358 partidos comunes, 17 sólo en uno y 18 sólo
  // en el otro: son revisiones distintas de la misma carga (el repositorio
  // también tiene carga_albergue_2026rev.sql y un CSV "rev").
  //
  // Consecuencia: no pueden validarse entre sí, y sin las filas reales de
  // `partidos` en Supabase no hay forma de saber cuál corresponde a
  // producción. Cada conjunto sólo sirve como golden de sí mismo.
  test('los tres conjuntos del Albergue difieren en número de partidos (documentado)', async () => {
    const porId = Object.fromEntries(DATASETS.map(d => [d.id, d]));
    const cuenta = async id => {
      const d = porId[id];
      const r = await runBatch({ players, csv: d.csv(), nombre: d.torneo, fecha: '2026-03-01' });
      return r.parsed.length;
    };
    assert.equal(await cuenta('albergue-2026-stadium'), 433);
    assert.equal(await cuenta('albergue-2026-simple'), 391);
    assert.equal(await cuenta('albergue-2026-carga-sql'), 376);
  });

  test('aun así, los tres mantienen la suma cero por separado', async () => {
    for (const id of ['albergue-2026-stadium', 'albergue-2026-simple', 'albergue-2026-carga-sql']) {
      const d = DATASETS.find(x => x.id === id);
      const r = await runBatch({ players, csv: d.csv(), nombre: d.torneo, fecha: '2026-03-01' });
      const neto = r.resultados.reduce((s, x) => s + (x.rating_fin - x.rating_inicio), 0);
      assert.equal(neto, 0, `${id} no cuadra a cero`);
    }
  });
});
