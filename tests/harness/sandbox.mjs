/**
 * FPTM · Fase 0 — Sandbox para el pipeline oficial de ratings
 *
 * Carga las funciones REALES de index.html en un contexto vm, con lo mínimo
 * imprescindible alrededor: un DOM de mentira y stubs de red que registran
 * las llamadas en vez de hacerlas.
 *
 * Regla del sandbox: NO reimplementa nada del pipeline oficial. Todo lo que
 * calcula un rating viene textualmente de index.html. Los stubs solo cubren
 * el entorno del navegador (document, alert) y la capa de red (sbPost,
 * sbPatch), para poder observar QUÉ se escribiría sin escribir nada.
 *
 * Nada aquí toca Supabase. No hay red. No hay credenciales.
 */

import vm from 'node:vm';
import { extractAll } from './extract.mjs';

/** Declaraciones de index.html que forman el pipeline oficial de ratings. */
export const PIPELINE_DECLS = [
  'INSC_CATEGORIES',   // catálogo de categorías (dobles, stadiumId, …)
  'POINT_TABLE',       // tabla oficial de puntos por diferencia de rating
  'getPoints',         // cálculo oficial por partido
  'idFptm',            // parseo del id de federación entre varios proveedores
  'catDesdeEvento',    // nombre de evento Stadium → categoría
  'esCategoriaDobles', // exclusión de dobles
  'faseYRonda',        // fase / grupo / ronda / orden
  'subirLoadTexto',    // parseo del CSV (Stadium y formato simple)
  'subirProcesarCsv',  // cálculo de deltas + vista previa (borrador)
  'subirApplyRatings', // aplicación final: partidos + net por jugador
];

function makeElement(id) {
  const el = {
    id,
    _text: '',
    _html: '',
    value: '',
    disabled: false,
    style: { cssText: '', display: '' },
    classList: {
      _s: new Set(),
      add(c) { this._s.add(c); },
      remove(c) { this._s.delete(c); },
      contains(c) { return this._s.has(c); },
    },
    scrollIntoView() {},
    appendChild() {},
    removeChild() {},
    querySelectorAll: () => [],
    addEventListener() {},
  };
  Object.defineProperty(el, 'textContent', {
    get() { return el._text; },
    set(v) { el._text = String(v); el._html = String(v); },
  });
  Object.defineProperty(el, 'innerHTML', {
    get() { return el._html; },
    set(v) { el._html = String(v); },
  });
  return el;
}

/**
 * Construye un sandbox cargado con el pipeline oficial.
 *
 * @param {object}   opts
 * @param {Array}    opts.players  ALL_PLAYERS: [{ id, name, rating, club }]
 * @returns  el contexto vm, más `calls` (red registrada) y `el(id)` (DOM).
 */
export async function loadPipeline({ players = [] } = {}) {
  const decls = await extractAll(PIPELINE_DECLS);

  const elements = new Map();
  const el = id => {
    if (!elements.has(id)) elements.set(id, makeElement(id));
    return elements.get(id);
  };

  // Red registrada, nunca ejecutada.
  const calls = { sbPost: [], sbPatch: [], sbGet: [], alerts: [] };

  const ctx = {
    // ── Entorno de navegador (stub) ───────────────────────────────────────
    document: {
      getElementById: el,
      querySelectorAll: () => [],
      createElement: () => makeElement('created'),
      addEventListener() {},
      body: { appendChild() {}, removeChild() {}, classList: { toggle: () => false } },
    },
    window: { innerWidth: 1280, addEventListener() {}, prompt: () => null },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    console,
    setTimeout, clearTimeout,
    alert: msg => { calls.alerts.push(String(msg)); },

    // ── Estado del pipeline ───────────────────────────────────────────────
    // Copia: subirApplyRatings escribe `p.rating` sobre ALL_PLAYERS. Sin
    // clonar, dos tests seguidos compartirían ratings y el segundo partiría
    // de valores ya modificados.
    ALL_PLAYERS: players.map(p => ({ ...p })),
    RANK_BY_ID: {},
    subirCsvRows: [],
    subirPending: [],
    currentUser: { email: 'phase0-characterization@local' }, // sólo pasa el guard
    filterPlayers: () => {},
    showLogin: () => { throw new Error('showLogin() — el sandbox debe tener currentUser'); },

    // ── Capa de red: registra, no escribe ─────────────────────────────────
    sbPost: async (table, payload) => {
      calls.sbPost.push({ table, payload });
      // torneos devuelve [{id}] — el pipeline lo usa como torneo_id
      if (table === 'torneos') return [{ id: 9000 + calls.sbPost.length }];
      return [];
    },
    sbPatch: async (table, filter, payload) => {
      calls.sbPatch.push({ table, filter, payload });
      return [];
    },
    sbGet: async (table, qs) => { calls.sbGet.push({ table, qs }); return []; },
  };
  ctx.globalThis = ctx;

  const context = vm.createContext(ctx);

  // Un solo script, no uno por declaración: en index.html todas comparten el
  // mismo ámbito, y `const` no se propaga entre scripts distintos de vm
  // (esCategoriaDobles no vería INSC_CATEGORIES). El epílogo publica los
  // `const` en globalThis para que los tests puedan leerlos.
  const epilogo = decls.map(d => `globalThis.${d.name} = ${d.name};`).join('\n');
  const script = decls.map(d => `/* index.html:${d.line} */\n${d.source}`).join('\n\n') + '\n\n' + epilogo;

  try {
    vm.runInContext(script, context, { filename: 'index.html (pipeline oficial)' });
  } catch (e) {
    throw new Error(`No se pudo evaluar el pipeline oficial extraído de index.html: ${e.message}`);
  }

  return { ctx: context, calls, el, decls };
}

/**
 * Corre un lote completo: CSV(s) → parseo → deltas → aplicación,
 * usando exclusivamente las funciones de index.html.
 *
 * Devuelve lo que el pipeline oficial ESCRIBIRÍA, sin escribirlo.
 */
export async function runBatch({ players, csv, nombre = 'Torneo Test', fecha = '2026-01-01', categoria = '' }) {
  const { ctx, calls, el } = await loadPipeline({ players });

  el('subirTorneoNombre').value = nombre;
  el('subirTorneoFecha').value = fecha;
  el('subirCategoria').value = categoria;

  // Varios archivos = un solo lote (regla del rating congelado del torneo).
  const texto = Array.isArray(csv) ? mergeCsv(csv) : csv;

  ctx.subirLoadTexto(texto, Array.isArray(csv) ? `${csv.length} archivos` : 'test.csv');
  const parsed = toHost(ctx.subirCsvRows);

  ctx.subirProcesarCsv();
  const pending = toHost(ctx.subirPending);
  const previewHtml = el('subirResultBody').innerHTML;
  const previewShown = el('subirResult').classList.contains('show');

  await ctx.subirApplyRatings();

  const partidos = toHost(calls.sbPost.filter(c => c.table === 'partidos').map(c => c.payload));
  const resultados = toHost(
    calls.sbPost
      .filter(c => c.table === 'resultados_evento')
      .flatMap(c => (c.payload && typeof c.payload.length === 'number' ? Array.from(c.payload) : [c.payload]))
  );
  const ratingWrites = toHost(
    calls.sbPatch
      .filter(c => c.table === 'Base%20de%20Datos')
      .map(c => ({ filter: c.filter, newRating: c.payload['New Rating'] }))
  );

  return {
    ctx, calls, el,
    parsed, pending, previewHtml, previewShown,
    partidos, resultados, ratingWrites,
    status: el('subirCsvStatus'),
  };
}

/**
 * Copia arrays/objetos que vienen del vm a este realm.
 * Sin esto, assert.deepEqual los rechaza por prototipo aunque el valor sea
 * idéntico ("same structure but not reference-equal").
 */
export function toHost(arr) {
  return Array.from(arr ?? [], x => (x && typeof x === 'object' ? { ...x } : x));
}

/** Une varios CSV conservando sólo el primer encabezado (igual que subirLoadFiles). */
export function mergeCsv(textos) {
  const partes = textos.map((t, i) => {
    const ls = String(t).trim().split(/\r?\n/).filter(l => l.trim());
    return i === 0 ? ls : ls.slice(1);
  });
  return partes.flat().join('\n');
}

/** Constructor de jugadores para los tests. */
export function player(id, rating, name = `P${id}`, club = '') {
  return { id, rating, name, club };
}
