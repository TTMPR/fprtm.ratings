/**
 * FPTM · Fase 0 — Caracterización del núcleo oficial de rating
 * Objetivos B1–B5: fronteras de POINT_TABLE, empate, favorito, underdog, suma cero.
 *
 * ESTOS TESTS FIJAN EL COMPORTAMIENTO ACTUAL, NO LO VALIDAN.
 * Su única función es detectar cambios. Un fallo significa "el comportamiento
 * oficial cambió", no "el cálculo está mal". Si un cambio es intencional, se
 * actualiza el test a propósito y se deja constancia.
 *
 * Fuente única de verdad: getPoints() y POINT_TABLE en index.html.
 * No se consulta ninguna implementación del repositorio antiguo kileaaa.com.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { loadPipeline } from './harness/sandbox.mjs';

const { ctx } = await loadPipeline();
const { getPoints, POINT_TABLE } = ctx;

// La tabla oficial tal y como está hoy en index.html. Duplicarla aquí es
// deliberado: si alguien edita POINT_TABLE, este test lo delata.
const TABLA_ESPERADA = [
  { maxDiff: 24, fav: 8, underdog: 8 },
  { maxDiff: 49, fav: 7, underdog: 10 },
  { maxDiff: 99, fav: 5, underdog: 12 },
  { maxDiff: 149, fav: 3, underdog: 15 },
  { maxDiff: 199, fav: 2, underdog: 20 },
  { maxDiff: 249, fav: 1, underdog: 26 },
  { maxDiff: Infinity, fav: 0, underdog: 32 },
];

describe('B1 · POINT_TABLE — estructura y fronteras', () => {
  test('la tabla oficial no ha cambiado', () => {
    // Array.from/spread devuelven objetos de este realm; los del vm tienen
    // otro prototipo y deepEqual estricto los rechazaría por eso, no por valor.
    assert.deepEqual(Array.from(POINT_TABLE, r => ({ ...r })), TABLA_ESPERADA);
  });

  // Cada frontera se prueba por ambos lados: el último valor de un tramo
  // y el primero del siguiente.
  const FRONTERAS = [
    { diff: 0, fav: 8, und: 8 },
    { diff: 23, fav: 8, und: 8 },
    { diff: 24, fav: 8, und: 8 },   // último del tramo 0–24
    { diff: 25, fav: 7, und: 10 },  // primero del tramo 25–49
    { diff: 49, fav: 7, und: 10 },
    { diff: 50, fav: 5, und: 12 },
    { diff: 99, fav: 5, und: 12 },
    { diff: 100, fav: 3, und: 15 },
    { diff: 149, fav: 3, und: 15 },
    { diff: 150, fav: 2, und: 20 },
    { diff: 199, fav: 2, und: 20 },
    { diff: 200, fav: 1, und: 26 },
    { diff: 249, fav: 1, und: 26 },
    { diff: 250, fav: 0, und: 32 },  // primero del tramo abierto
    { diff: 400, fav: 0, und: 32 },
    { diff: 1500, fav: 0, und: 32 },
  ];

  for (const { diff, fav, und } of FRONTERAS) {
    test(`diferencia ${diff} → favorito ${fav}, underdog ${und}`, () => {
      const base = 1500;
      // A es el favorito (rating mayor)
      assert.equal(getPoints(base + diff, base, true).aGain, fav,
        `favorito gana con diferencia ${diff}`);
      assert.equal(getPoints(base + diff, base, false).bGain, und,
        `underdog gana con diferencia ${diff}`);
    });
  }
});

describe('B2 · Comportamiento con ratings iguales', () => {
  test('empate de rating: 8 puntos gane quien gane', () => {
    assert.deepEqual({ ...getPoints(1500, 1500, true) }, { aGain: 8, bGain: -8 });
    assert.deepEqual({ ...getPoints(1500, 1500, false) }, { aGain: -8, bGain: 8 });
  });

  test('con ratings iguales A se considera el favorito (rA >= rB)', () => {
    // Documenta el desempate interno: `aIsFav = rA >= rB`. En el tramo 0–24
    // no se nota (fav y underdog valen 8), pero la rama existe.
    assert.equal(getPoints(1500, 1500, true).aGain, 8);
  });

  test('es simétrico respecto al orden de los jugadores', () => {
    const ab = getPoints(1700, 1500, true);   // gana A (favorito)
    const ba = getPoints(1500, 1700, false);  // gana B (favorito)
    assert.equal(ab.aGain, ba.bGain);
    assert.equal(ab.bGain, ba.aGain);
  });
});

describe('B3 · Victoria del favorito', () => {
  const CASOS = [
    { rA: 1500, rB: 1490, esperado: 8 },
    { rA: 1530, rB: 1500, esperado: 7 },
    { rA: 1560, rB: 1500, esperado: 5 },
    { rA: 1620, rB: 1500, esperado: 3 },
    { rA: 1680, rB: 1500, esperado: 2 },
    { rA: 1720, rB: 1500, esperado: 1 },
    { rA: 1900, rB: 1500, esperado: 0 },
  ];
  for (const { rA, rB, esperado } of CASOS) {
    test(`${rA} vence a ${rB} → +${esperado}`, () => {
      const { aGain, bGain } = getPoints(rA, rB, true);
      assert.equal(aGain, esperado);
      assert.equal(bGain, -esperado);
    });
  }

  test('con diferencia de 250+ el favorito no gana nada y el underdog no pierde nada', () => {
    const { aGain, bGain } = getPoints(2000, 1500, true);
    assert.equal(aGain, 0);
    assert.equal(Math.abs(bGain), 0);
  });
});

describe('B4 · Victoria del underdog', () => {
  const CASOS = [
    { rA: 1490, rB: 1500, esperado: 8 },
    { rA: 1470, rB: 1500, esperado: 10 },
    { rA: 1440, rB: 1500, esperado: 12 },
    { rA: 1380, rB: 1500, esperado: 15 },
    { rA: 1320, rB: 1500, esperado: 20 },
    { rA: 1280, rB: 1500, esperado: 26 },
    { rA: 1100, rB: 1500, esperado: 32 },
  ];
  for (const { rA, rB, esperado } of CASOS) {
    test(`${rA} vence a ${rB} → +${esperado}`, () => {
      const { aGain, bGain } = getPoints(rA, rB, true);
      assert.equal(aGain, esperado);
      assert.equal(bGain, -esperado);
    });
  }

  test('el underdog gana más cuanto mayor es la diferencia (monótono no decreciente)', () => {
    let previo = 0;
    for (let diff = 0; diff <= 400; diff += 5) {
      const pts = getPoints(1500 - diff, 1500, true).aGain;
      assert.ok(pts >= previo, `diferencia ${diff}: ${pts} < ${previo}`);
      previo = pts;
    }
  });
});

describe('B5 · Suma cero', () => {
  test('aGain === -bGain en todo el rango', () => {
    for (let rA = 800; rA <= 2400; rA += 17) {
      for (let rB = 800; rB <= 2400; rB += 23) {
        for (const winA of [true, false]) {
          const { aGain, bGain } = getPoints(rA, rB, winA);
          assert.equal(aGain + bGain, 0,
            `no suma cero en rA=${rA} rB=${rB} winA=${winA}: ${aGain} / ${bGain}`);
        }
      }
    }
  });

  test('el ganador nunca pierde puntos y el perdedor nunca gana', () => {
    for (let rA = 900; rA <= 2200; rA += 31) {
      for (let rB = 900; rB <= 2200; rB += 37) {
        const ganaA = getPoints(rA, rB, true);
        assert.ok(ganaA.aGain >= 0, `ganador con delta negativo: ${rA} vs ${rB}`);
        assert.ok(ganaA.bGain <= 0, `perdedor con delta positivo: ${rA} vs ${rB}`);
      }
    }
  });

  test('los puntos intercambiados son siempre enteros', () => {
    for (let d = 0; d <= 600; d += 7) {
      const { aGain } = getPoints(1500 + d, 1500, true);
      assert.ok(Number.isInteger(aGain), `no entero con diferencia ${d}: ${aGain}`);
    }
  });
});
