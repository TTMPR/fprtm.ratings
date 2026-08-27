/**
 * FPTM · Fase 0 — Carga de datos históricos oficiales del repositorio
 *
 * Todo lo que se lee aquí es un artefacto del proceso oficial de
 * ratings.ttmpr.xyz que ya está en este repositorio:
 *
 *   restore_rating_backup.sql   snapshot oficial de Rating por Member ID,
 *                               tomado ANTES del Albergue Olímpico 2026
 *   TODOS -Albuergue...csv      export real de Stadium Compete de ese torneo
 *   albergue_olimpico_2026.csv  lista de partidos en formato simple
 *   carga_*.sql                 listas de partidos tal y como se cargaron
 *
 * No se lee, importa ni consulta nada del repositorio antiguo kileaaa.com.
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = f => readFileSync(path.join(ROOT, f), 'utf8');

/**
 * Snapshot oficial de ratings anterior al Albergue Olímpico 2026.
 * @returns {Map<number, number>} Member ID → Rating
 */
export function ratingsSnapshot() {
  const src = read('restore_rating_backup.sql');
  const re = /SET\s+"Rating"\s*=\s*(-?\d+)\s+WHERE\s+"Member ID"\s*=\s*(\d+)/g;
  const map = new Map();
  for (const m of src.matchAll(re)) map.set(Number(m[2]), Number(m[1]));
  if (map.size === 0) throw new Error('restore_rating_backup.sql: no se extrajo ningún rating');
  return map;
}

/** Convierte el snapshot en el ALL_PLAYERS que espera el pipeline. */
export function playersFromSnapshot(snapshot) {
  // El nombre y el club no intervienen en ningún cálculo de rating; sólo
  // viajan a resultados_evento. Se usan marcadores estables para que los
  // ficheros golden no dependan de datos personales.
  return Array.from(snapshot, ([id, rating]) => ({
    id, rating, name: `#${id}`, club: '',
  }));
}

/** Contenido crudo de un fichero histórico. */
export const raw = name => read(name);

/**
 * Extrae los pares (ganador, perdedor) de un cargador carga_*.sql y los
 * devuelve en el formato simple que el importador entiende.
 *
 * El encabezado se omite a propósito: el filtro de index.html sólo descarta
 * la primera línea si contiene jugador/player/ganador/winner, así que un
 * "pA,pB,win" se colaría como partido (ver importer.test.mjs, B14).
 */
export function matchesFromCargaSql(file) {
  const src = read(file);
  const bloque = src.match(/INSERT INTO _matches[^;]*?VALUES([\s\S]*?);/i);
  if (!bloque) throw new Error(`${file}: no se encontró el bloque INSERT INTO _matches`);
  const pares = [...bloque[1].matchAll(/\(\s*(\d+)\s*,\s*(\d+)\s*\)/g)];
  if (!pares.length) throw new Error(`${file}: no se extrajo ningún par ganador/perdedor`);
  return pares.map(m => `#${m[1]},#${m[2]},A`).join('\n');
}

/**
 * Conjuntos históricos que el importador oficial ACTUAL puede consumir.
 *
 * Nota: torneo_1700_under.csv, albergue_olimpico_march2026.csv y
 * albergue.olimpico.2026rev usan un formato Round/WinnerID/LoserID que el
 * importador de index.html NO reconoce — se cargaron en su día con los
 * scripts de Python del repositorio. Quedan documentados como hueco en
 * PHASE0_REPORT.md en vez de forzarlos aquí.
 */
export const DATASETS = [
  {
    id: 'albergue-2026-stadium',
    torneo: 'Albergue Olímpico 2026',
    fuente: 'TODOS -Albuergue.Olimpico.2026.csv',
    formato: 'Stadium Compete',
    csv: () => raw('TODOS -Albuergue.Olimpico.2026.csv'),
  },
  {
    id: 'albergue-2026-simple',
    torneo: 'Albergue Olímpico 2026',
    fuente: 'albergue_olimpico_2026.csv',
    formato: 'simple (pA,pB,win)',
    csv: () => raw('albergue_olimpico_2026.csv'),
  },
  {
    id: 'albergue-2026-carga-sql',
    torneo: 'Albergue Olímpico 2026',
    fuente: 'carga_albergue_2026.sql',
    formato: 'lista de partidos del cargador SQL',
    csv: () => matchesFromCargaSql('carga_albergue_2026.sql'),
  },
  {
    id: 'open-2026-carga-sql',
    torneo: 'Open 2026',
    fuente: 'carga_open_2026.sql',
    formato: 'lista de partidos del cargador SQL',
    csv: () => matchesFromCargaSql('carga_open_2026.sql'),
  },
  {
    id: '1700-under-carga-sql',
    torneo: '1700 Under',
    fuente: 'carga_1700_under.sql',
    formato: 'lista de partidos del cargador SQL',
    csv: () => matchesFromCargaSql('carga_1700_under.sql'),
  },
];

/** Resumen determinista de un lote, para comparar contra el golden. */
export function resumen(r) {
  const orden = (a, b) => a.id_jugador - b.id_jugador;
  return {
    partidosParseados: r.parsed.length,
    partidosCalculados: r.pending.length,
    partidosGuardados: r.partidos.length,
    participantes: r.resultados.length,
    actualizacionesDeRating: r.ratingWrites.length,
    sumaNetaDeDeltas: r.resultados.reduce((s, x) => s + (x.rating_fin - x.rating_inicio), 0),
    retirados: r.pending.filter(p => p.retired).length,
    jugadores: Array.from(r.resultados).sort(orden).map(x => ({
      id: x.id_jugador,
      inicio: x.rating_inicio,
      fin: x.rating_fin,
      delta: x.rating_fin - x.rating_inicio,
      ganados: x.ganados,
      perdidos: x.perdidos,
    })),
  };
}
