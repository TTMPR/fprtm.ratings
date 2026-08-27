/**
 * FPTM · Fase 0 — Caracterización del lote de torneo
 * Objetivos B6–B8: rating congelado al inicio, varios partidos por jugador,
 * una sola aplicación neta al cierre.
 *
 * ESTOS TESTS FIJAN EL COMPORTAMIENTO ACTUAL, NO LO VALIDAN.
 *
 * Todo lo que se ejercita aquí sale de index.html (subirLoadTexto →
 * subirProcesarCsv → subirApplyRatings). El sandbox solo intercepta la capa
 * de red: registra lo que se escribiría en `partidos`, `resultados_evento` y
 * `Base de Datos` sin escribir nada. No se toca Supabase.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { runBatch, player } from './harness/sandbox.mjs';

const H = 'winnerMembershipIds,loserMembershipIds,description,eventName,drawName,scores';
const win = (ganador, perdedor, desc = 'Final', ev = '1700 o Menos', draw = 'Llave Principal', sc = '11,9') =>
  `fptm|${ganador},fptm|${perdedor},${desc},${ev},${draw},"${sc}"`;
const csv = (...filas) => [H, ...filas].join('\n');

const ratingDe = (writes, id) =>
  writes.find(w => w.filter.includes(`eq.${id}`))?.newRating;

describe('B6 · El rating se congela al inicio del torneo', () => {
  test('todos los partidos usan el rating de llegada, no uno acumulado', async () => {
    // A gana dos veces seguidas. Si el rating se actualizara entre partidos,
    // el segundo cálculo partiría de 1508 y daría puntos distintos.
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B'), player(3, 1500, 'C')],
      csv: csv(win(1, 2), win(1, 3)),
    });

    assert.equal(r.pending.length, 2);
    assert.equal(r.pending[0].rA, 1500, 'primer partido parte de 1500');
    assert.equal(r.pending[1].rA, 1500, 'segundo partido TAMBIÉN parte de 1500');
    assert.equal(r.pending[0].aGain, 8);
    assert.equal(r.pending[1].aGain, 8);
  });

  test('rating_a_antes y rating_b_antes siempre son el rating de llegada', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1400, 'B'), player(3, 1600, 'C')],
      csv: csv(win(1, 2), win(1, 3), win(2, 3)),
    });
    for (const p of r.partidos) {
      if (p.jugador_a_id === 1 || p.jugador_b_id === 1) {
        const campo = p.jugador_a_id === 1 ? 'rating_a_antes' : 'rating_b_antes';
        assert.equal(p[campo], 1500, `${campo} debe ser el rating de llegada de A`);
      }
    }
  });

  test('el orden de los partidos no cambia el resultado neto', async () => {
    const jugadores = [player(1, 1500, 'A'), player(2, 1400, 'B'), player(3, 1600, 'C')];
    const directo = await runBatch({ players: jugadores, csv: csv(win(1, 2), win(1, 3)) });
    const invertido = await runBatch({ players: jugadores, csv: csv(win(1, 3), win(1, 2)) });
    assert.equal(ratingDe(directo.ratingWrites, 1), ratingDe(invertido.ratingWrites, 1));
  });
});

describe('B7 · Varios partidos del mismo jugador en un torneo', () => {
  test('los deltas se acumulan y se suman al rating de llegada', async () => {
    // A(1500): gana a B(1400) → +3 ; gana a C(1600) → +15 ; pierde con D(1500) → -8
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1400, 'B'), player(3, 1600, 'C'), player(4, 1500, 'D')],
      csv: csv(win(1, 2), win(1, 3), win(4, 1)),
    });

    const deltas = r.pending.map(p => (p.idA === 1 ? p.aGain : p.bGain));
    assert.deepEqual(deltas, [3, 15, -8]);
    assert.equal(ratingDe(r.ratingWrites, 1), 1500 + 3 + 15 - 8);
  });

  test('ganados y perdidos se cuentan por jugador', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B'), player(3, 1500, 'C'), player(4, 1500, 'D')],
      csv: csv(win(1, 2), win(1, 3), win(4, 1)),
    });
    const a = r.resultados.find(x => x.id_jugador === 1);
    assert.equal(a.ganados, 2);
    assert.equal(a.perdidos, 1);
  });

  test('resultados_evento guarda rating_inicio y rating_fin por jugador', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1400, 'B'), player(3, 1600, 'C')],
      csv: csv(win(1, 2), win(1, 3)),
    });
    const a = r.resultados.find(x => x.id_jugador === 1);
    assert.equal(a.rating_inicio, 1500);
    assert.equal(a.rating_fin, 1518);
  });

  test('un torneo entero mantiene la suma cero global', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1400, 'B'), player(3, 1600, 'C'), player(4, 1750, 'D')],
      csv: csv(win(1, 2), win(1, 3), win(4, 1), win(2, 3), win(4, 2)),
    });
    const neto = r.resultados.reduce((s, x) => s + (x.rating_fin - x.rating_inicio), 0);
    assert.equal(neto, 0, 'el torneo no crea ni destruye puntos');
  });
});

describe('B8 · Una sola aplicación neta al cierre', () => {
  test('exactamente un UPDATE de rating por jugador, sin importar cuántos partidos jugó', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B'), player(3, 1500, 'C'), player(4, 1500, 'D')],
      csv: csv(win(1, 2), win(1, 3), win(1, 4), win(2, 3)),
    });

    const ids = r.ratingWrites.map(w => w.filter);
    assert.equal(ids.length, new Set(ids).size, 'ningún jugador se actualiza dos veces');
    assert.equal(r.ratingWrites.length, 4, 'un UPDATE por participante');
    assert.equal(r.partidos.length, 4, 'un registro por partido');
  });

  test('la columna que se escribe es "New Rating"', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B')],
      csv: csv(win(1, 2)),
    });
    const patch = r.calls.sbPatch.find(c => c.table === 'Base%20de%20Datos');
    assert.ok(patch, 'se escribe en Base de Datos');
    assert.deepEqual(Object.keys({ ...patch.payload }), ['New Rating']);
  });

  test('el torneo se crea antes de escribir partidos', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B')],
      csv: csv(win(1, 2)),
    });
    assert.equal(r.calls.sbPost[0].table, 'torneos');
    assert.ok(r.partidos.every(p => p.torneo_id != null), 'cada partido lleva torneo_id');
  });

  test('resultados_evento se inserta una vez por participante', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B'), player(3, 1500, 'C')],
      csv: csv(win(1, 2), win(1, 3), win(2, 3)),
    });
    const ids = r.resultados.map(x => x.id_jugador).sort();
    assert.deepEqual(ids, [1, 2, 3]);
  });

  test('CARACTERÍSTICA PRESERVADA · partidos.rating_*_despues es por partido, no acumulado', async () => {
    // rating_a_despues = rating de llegada + delta DE ESE partido.
    // No es el rating del jugador después de ese partido en el orden real del
    // torneo, ni su rating final. Para el rating final está resultados_evento.
    // Se documenta aquí para que nadie lo lea como un histórico cronológico.
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B'), player(3, 1500, 'C')],
      csv: csv(win(1, 2), win(1, 3)),
    });

    assert.equal(r.partidos[0].rating_a_despues, 1508);
    assert.equal(r.partidos[1].rating_a_despues, 1508, 'no 1516: no acumula entre partidos');
    assert.equal(ratingDe(r.ratingWrites, 1), 1516, 'el neto real sí acumula');
  });
});
