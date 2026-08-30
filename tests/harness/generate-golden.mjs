#!/usr/bin/env node
/**
 * FPTM · Fase 0 — Generación de los ficheros golden del replay histórico
 *
 * Corre cada conjunto histórico por el pipeline oficial de index.html y
 * guarda el resultado en tests/golden/. A partir de ahí, replay.test.mjs
 * compara contra esos ficheros: cualquier diferencia significa que el
 * comportamiento oficial cambió.
 *
 * Los golden NO son una verdad matemática: son una foto del comportamiento
 * actual. Regenerarlos sólo tiene sentido cuando un cambio del pipeline es
 * deliberado y está aprobado — y el diff debe revisarse a mano.
 *
 *   node tests/harness/generate-golden.mjs            (muestra el diff)
 *   node tests/harness/generate-golden.mjs --write    (escribe)
 *
 * No toca Supabase. No hay red.
 */

import { writeFileSync, existsSync, readFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runBatch } from './sandbox.mjs';
import { DATASETS, ratingsSnapshot, playersFromSnapshot, resumen } from './fixtures.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const GOLDEN = path.resolve(HERE, '..', 'golden');
const ESCRIBIR = process.argv.includes('--write');

mkdirSync(GOLDEN, { recursive: true });

const snapshot = ratingsSnapshot();
const players = playersFromSnapshot(snapshot);
console.log(`Snapshot oficial: ${snapshot.size} jugadores (restore_rating_backup.sql)\n`);

let cambios = 0;

for (const ds of DATASETS) {
  const r = await runBatch({
    players,
    csv: ds.csv(),
    nombre: ds.torneo,
    fecha: '2026-03-01',
  });

  const datos = {
    _meta: {
      dataset: ds.id,
      torneo: ds.torneo,
      fuente: ds.fuente,
      formato: ds.formato,
      snapshot: 'restore_rating_backup.sql',
      jugadoresEnSnapshot: snapshot.size,
      nota: 'Foto del comportamiento del pipeline oficial. No es una verdad matemática.',
    },
    ...resumen(r),
  };

  const file = path.join(GOLDEN, `${ds.id}.json`);
  const texto = JSON.stringify(datos, null, 2) + '\n';
  const previo = existsSync(file) ? readFileSync(file, 'utf8') : null;

  if (previo === texto) {
    console.log(`= ${ds.id.padEnd(28)} sin cambios (${datos.participantes} participantes)`);
    continue;
  }

  cambios++;
  if (previo === null) {
    console.log(`+ ${ds.id.padEnd(28)} NUEVO — ${datos.partidosGuardados} partidos, ${datos.participantes} participantes`);
  } else {
    const a = JSON.parse(previo);
    console.log(`~ ${ds.id.padEnd(28)} CAMBIÓ`);
    for (const k of ['partidosParseados', 'partidosGuardados', 'participantes', 'sumaNetaDeDeltas', 'retirados']) {
      if (a[k] !== datos[k]) console.log(`    ${k}: ${a[k]} → ${datos[k]}`);
    }
  }
  if (ESCRIBIR) writeFileSync(file, texto);
}

if (!ESCRIBIR && cambios) {
  console.log(`\n${cambios} fichero(s) golden difieren. Revisa el diff y, si el cambio es`);
  console.log('deliberado y está aprobado, vuelve a correr con --write.');
  process.exitCode = 1;
} else if (ESCRIBIR) {
  console.log(`\nEscritos en ${GOLDEN}`);
}
