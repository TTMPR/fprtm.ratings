/**
 * FPTM · Fase 0 — Caracterización del importador oficial
 * Objetivos B9–B15: fusión multi-archivo, retirados, W/O, dobles,
 * parseo de IDs, filas omitidas, y el borrador/vista previa.
 *
 * ESTOS TESTS FIJAN EL COMPORTAMIENTO ACTUAL, NO LO VALIDAN.
 * Varios documentan comportamiento que puede sorprender; están marcados
 * como CARACTERÍSTICA PRESERVADA y NO deben "arreglarse" sin una decisión
 * explícita sobre el pipeline oficial.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { runBatch, loadPipeline, player, mergeCsv } from './harness/sandbox.mjs';

const H = 'winnerMembershipIds,loserMembershipIds,description,eventName,drawName,scores';
const fila = (g, p, desc = 'Final', ev = '1700 o Menos', draw = 'Llave Principal', sc = '11,9') =>
  `${g},${p},${desc},${ev},${draw},"${sc}"`;
const win = (g, p, ...rest) => fila(`fptm|${g}`, `fptm|${p}`, ...rest);
const csv = (...filas) => [H, ...filas].join('\n');

const JUGADORES = [player(1, 1500, 'A'), player(2, 1400, 'B'), player(3, 1600, 'C')];

// Instancia sólo para las funciones puras de B13 (idFptm).
const { ctx } = await loadPipeline();
const ratingDe = (w, id) => w.find(x => x.filter.includes(`eq.${id}`))?.newRating;

describe('B9 · Fusión multi-archivo / multi-fin-de-semana', () => {
  test('varios archivos forman un solo lote y comparten el rating de llegada', async () => {
    const f1 = csv(win(1, 2));
    const f2 = csv(win(1, 3));
    const r = await runBatch({ players: JUGADORES, csv: [f1, f2] });

    assert.equal(r.parsed.length, 2, 'se conservan los partidos de ambos archivos');
    assert.ok(r.pending.every(p => (p.idA === 1 ? p.rA : p.rB) === 1500),
      'A parte de 1500 en los dos archivos');
    assert.equal(ratingDe(r.ratingWrites, 1), 1500 + 3 + 15);
  });

  test('la fusión descarta el encabezado de los archivos siguientes', () => {
    const unido = mergeCsv([csv(win(1, 2)), csv(win(1, 3))]);
    const encabezados = unido.split('\n').filter(l => l.startsWith('winnerMembershipIds'));
    assert.equal(encabezados.length, 1);
  });

  test('subir por separado NO es equivalente — de ahí la regla de un solo lote', async () => {
    const juntos = await runBatch({ players: JUGADORES, csv: [csv(win(1, 2)), csv(win(1, 3))] });
    const soloPrimero = await runBatch({ players: JUGADORES, csv: csv(win(1, 2)) });

    assert.equal(ratingDe(juntos.ratingWrites, 1), 1518);
    assert.equal(ratingDe(soloPrimero.ratingWrites, 1), 1503);
  });
});

describe('B10 · Retirados', () => {
  test('un partido marcado Retired no mueve el rating de ninguno de los dos', async () => {
    const r = await runBatch({
      players: [player(1, 1300, 'A'), player(2, 1900, 'B')],
      csv: csv(win(1, 2, 'Retired')),
    });
    assert.equal(r.pending[0].retired, true);
    assert.equal(r.pending[0].aGain, 0);
    assert.equal(r.pending[0].bGain, 0);
    assert.equal(ratingDe(r.ratingWrites, 1), 1300);
    assert.equal(ratingDe(r.ratingWrites, 2), 1900);
  });

  test('el partido se guarda con notas: "retired"', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B')],
      csv: csv(win(1, 2, 'Retired')),
    });
    assert.equal(r.partidos[0].notas, 'retired');
  });

  test('un retirado no cuenta como ganado ni como perdido', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B')],
      csv: csv(win(1, 2, 'Retired')),
    });
    const a = r.resultados.find(x => x.id_jugador === 1);
    assert.equal(a.ganados, 0);
    assert.equal(a.perdidos, 0);
  });

  test('el participante sigue apareciendo en resultados_evento', async () => {
    const r = await runBatch({
      players: [player(1, 1500, 'A'), player(2, 1500, 'B')],
      csv: csv(win(1, 2, 'Retired')),
    });
    assert.equal(r.resultados.length, 2);
    assert.equal(r.resultados[0].rating_inicio, r.resultados[0].rating_fin);
  });

  test('variantes de texto que el importador reconoce como retirado', async () => {
    for (const desc of ['Retired', 'retired', 'Retirado', 'RETIR', 'Se retiró']) {
      const r = await runBatch({
        players: [player(1, 1500, 'A'), player(2, 1500, 'B')],
        csv: csv(win(1, 2, desc)),
      });
      assert.equal(r.pending[0].retired, true, `"${desc}" debería marcarse retirado`);
    }
  });
});

describe('B11 · W/O (walkover)', () => {
  test('CARACTERÍSTICA PRESERVADA · W/O se trata igual que Retired: cero cambio para ambos', async () => {
    // El PRD (§7.6) describe otra cosa: "Default / W/O — el ganador gana
    // puntos; el que no se presenta los pierde". El pipeline oficial NO hace
    // eso: el mismo patrón /retired|retir|walkover|w\/o/i marca W/O como
    // retirado y ninguno de los dos se mueve.
    //
    // Este test fija el comportamiento REAL. Si algún día se decide alinear
    // el código con el PRD, este test debe cambiarse a propósito y quedar
    // constancia — no es un fallo que haya que "arreglar" sin esa decisión.
    for (const desc of ['W/O', 'Walkover', 'walkover', 'w/o']) {
      const r = await runBatch({
        players: [player(1, 1300, 'A'), player(2, 1900, 'B')],
        csv: csv(win(1, 2, desc)),
      });
      assert.equal(r.pending[0].retired, true, `"${desc}" se marca retirado`);
      assert.equal(r.pending[0].aGain, 0, `"${desc}": el ganador no gana puntos`);
      assert.equal(r.pending[0].bGain, 0, `"${desc}": el ausente no pierde puntos`);
    }
  });

  test('CARACTERÍSTICA PRESERVADA · "Default" NO se reconoce y sí puntúa', async () => {
    // El PRD usa "Default / W/O" como sinónimos, pero el patrón no incluye
    // "default": un partido descrito así se califica como un partido normal.
    const r = await runBatch({
      players: [player(1, 1300, 'A'), player(2, 1900, 'B')],
      csv: csv(win(1, 2, 'Default')),
    });
    assert.equal(r.pending[0].retired, false);
    assert.equal(r.pending[0].aGain, 32);
    assert.equal(r.pending[0].bGain, -32);
  });
});

describe('B12 · Exclusión de dobles', () => {
  test('las categorías de dobles no entran al lote', async () => {
    for (const ev of ['Dobles Abierto', 'dobles-abierto']) {
      const r = await runBatch({ players: JUGADORES, csv: csv(win(1, 2, 'Final', ev)) });
      assert.equal(r.parsed.length, 0, `"${ev}" debería excluirse`);
    }
  });

  test('cualquier evento cuyo nombre contenga "doble" se excluye', async () => {
    const r = await runBatch({ players: JUGADORES, csv: csv(win(1, 2, 'Final', 'Dobles Mixtos Sub-15')) });
    assert.equal(r.parsed.length, 0);
  });

  test('los individuales sí entran', async () => {
    for (const ev of ['1700 o Menos', 'Abierto (Open Individual)', '1500 o Menos']) {
      const r = await runBatch({ players: JUGADORES, csv: csv(win(1, 2, 'Final', ev)) });
      assert.equal(r.parsed.length, 1, `"${ev}" debería entrar`);
    }
  });

  test('un lote mixto conserva sólo los individuales', async () => {
    const r = await runBatch({
      players: JUGADORES,
      csv: csv(win(1, 2, 'Final', '1700 o Menos'), win(1, 3, 'Final', 'Dobles Abierto')),
    });
    assert.equal(r.parsed.length, 1);
    assert.equal(r.partidos.length, 1);
  });
});

describe('B13 · Parseo de IDs de jugador/proveedor', () => {
  test('toma el id de la federación sea cual sea su posición', () => {
    assert.equal(ctx.idFptm('fptm|10074,stadium-tt|1194249'), '10074');
    assert.equal(ctx.idFptm('stadium-tt|1194201,fptm|82512'), '82512');
  });

  test('acepta la variante "fprtm|"', () => {
    assert.equal(ctx.idFptm('fprtm|82512'), '82512');
  });

  test('no distingue mayúsculas', () => {
    assert.equal(ctx.idFptm('FPTM|55'), '55');
  });

  test('devuelve null cuando no hay id de federación', () => {
    for (const v of ['stadium-tt|999', '', null, undefined, 'fptm|', 'xfptm|77']) {
      assert.equal(ctx.idFptm(v), null, `${JSON.stringify(v)} debería dar null`);
    }
  });

  test('exige frontera de palabra: "xfptm|77" no cuela', () => {
    assert.equal(ctx.idFptm('xfptm|77'), null);
  });
});

describe('B14 · Filas omitidas e inválidas', () => {
  test('una fila sin id de federación en cualquiera de los dos lados se omite', async () => {
    const r = await runBatch({
      players: JUGADORES,
      csv: csv(
        win(1, 2),
        fila('stadium-tt|999', 'fptm|2'),
        fila('fptm|1', 'stadium-tt|888'),
        win(1, 3),
      ),
    });
    assert.equal(r.parsed.length, 2, 'sólo entran las dos filas completas');
  });

  test('las omisiones con datos se reportan al usuario', async () => {
    const r = await runBatch({
      players: JUGADORES,
      csv: csv(win(1, 2), fila('stadium-tt|999', 'fptm|2')),
    });
    assert.match(r.status.innerHTML, /omitido/i, 'el estado avisa de filas omitidas');
    assert.match(r.status.innerHTML, /Línea 3/, 'identifica la línea concreta');
  });

  test('una fila totalmente vacía se omite en silencio', async () => {
    const r = await runBatch({ players: JUGADORES, csv: csv(win(1, 2), fila('', '')) });
    assert.equal(r.parsed.length, 1);
    assert.doesNotMatch(r.status.innerHTML, /Línea 3/);
  });

  test('un jugador que no está en Base de Datos se descarta y se avisa', async () => {
    const r = await runBatch({ players: JUGADORES, csv: csv(win(1, 2), win(1, 9999)) });
    assert.equal(r.parsed.length, 2, 'el CSV se parsea entero');
    assert.equal(r.pending.length, 1, 'sólo se calcula el partido con ambos conocidos');
    assert.equal(r.partidos.length, 1);
    assert.match(r.status.textContent, /no encontrados: #9999/);
  });

  test('un CSV sin partidos válidos no escribe nada', async () => {
    const r = await runBatch({ players: JUGADORES, csv: csv(fila('stadium-tt|1', 'stadium-tt|2')) });
    assert.equal(r.parsed.length, 0);
    assert.equal(r.partidos.length, 0);
    assert.equal(r.ratingWrites.length, 0);
    assert.match(r.status.textContent, /No se encontraron partidos válidos/);
  });

  test('CARACTERÍSTICA PRESERVADA · en formato simple el encabezado "pA,pB,win" no se descarta', async () => {
    // El filtro de encabezado busca /jugador|player|ganador|winner/i.
    // "pA,pB,win" no coincide, así que la primera línea se parsea como si
    // fuera un partido y termina contada como jugador desconocido.
    // Afecta a albergue_olimpico_2026.csv, que usa exactamente ese encabezado.
    const r = await runBatch({ players: JUGADORES, csv: 'pA,pB,win\n#1,#2,A\n#3,#1,A' });
    assert.equal(r.parsed.length, 3, 'el encabezado entra como fila');
    assert.equal(r.pending.length, 2, 'pero no llega a partido: "pA" no existe');
    assert.match(r.status.textContent, /no encontrados/);
  });
});

describe('B15 · Borrador / vista previa antes de aplicar', () => {
  test('procesar genera vista previa sin escribir nada', async () => {
    const { ctx, calls, el } = await loadPipeline({ players: JUGADORES });
    el('subirTorneoNombre').value = 'Torneo Test';
    el('subirTorneoFecha').value = '2026-01-01';

    ctx.subirLoadTexto(csv(win(1, 2)), 'test.csv');
    ctx.subirProcesarCsv();

    assert.equal(calls.sbPost.length, 0, 'no se ha escrito ningún partido');
    assert.equal(calls.sbPatch.length, 0, 'no se ha tocado ningún rating');
    assert.ok(el('subirResult').classList.contains('show'), 'la vista previa se muestra');
  });

  test('la vista previa muestra rating de partida y rating resultante', async () => {
    const r = await runBatch({ players: JUGADORES, csv: csv(win(1, 2)) });
    assert.match(r.previewHtml, /1500/, 'muestra el rating de partida');
    assert.match(r.previewHtml, /1503/, 'muestra el rating tras el partido');
  });

  test('un retirado se muestra como "sin cambio"', async () => {
    const r = await runBatch({ players: JUGADORES, csv: csv(win(1, 2, 'Retired')) });
    assert.match(r.previewHtml, /sin cambio/);
    assert.match(r.previewHtml, /RETIRED/);
  });

  test('el botón de aplicar queda habilitado sólo tras procesar', async () => {
    const { ctx, el } = await loadPipeline({ players: JUGADORES });
    el('subirTorneoNombre').value = 'T';
    el('subirApplyBtn').disabled = true;

    ctx.subirLoadTexto(csv(win(1, 2)), 'test.csv');
    ctx.subirProcesarCsv();

    assert.equal(el('subirApplyBtn').disabled, false);
  });

  test('el desglose por categoría aparece antes de aplicar', async () => {
    const r = await runBatch({
      players: JUGADORES,
      csv: csv(win(1, 2, 'Final', '1700 o Menos'), win(1, 3, 'Final', '1500 o Menos')),
    });
    assert.match(r.status.innerHTML, /2 categorías detectadas/);
  });
});
