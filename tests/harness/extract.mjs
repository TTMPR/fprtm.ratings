/**
 * FPTM · Fase 0 — Extractor de declaraciones de index.html
 *
 * Los tests de caracterización tienen que ejercitar EL CÓDIGO DE PRODUCCIÓN,
 * no una copia. index.html es un archivo único sin módulos, así que este
 * extractor recorta declaraciones de nivel superior por nombre y las devuelve
 * como texto fuente, listo para evaluarse en un sandbox (ver sandbox.mjs).
 *
 * index.html NO se modifica. Si alguien mueve o renombra una función, la
 * extracción falla ruidosamente en vez de pasar en silencio.
 *
 * Cómo encuentra el final: el <script> de index.html mantiene las
 * declaraciones de nivel superior en la columna 0 y sus cuerpos indentados,
 * así que el cierre es la primera línea posterior que sea exactamente
 * "}", "};", "]" o "];" en la columna 0. Es deliberadamente tonto — contar
 * llaves rompería con los literales de expresión regular del archivo.
 */

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const INDEX_PATH = path.resolve(HERE, '..', '..', 'index.html');

let _lines = null;

async function lines() {
  if (_lines) return _lines;
  const src = await readFile(INDEX_PATH, 'utf8');
  _lines = src.split(/\r?\n/);
  return _lines;
}

const CLOSER = /^(?:\}|\};|\]|\];)$/;

function startPattern(name) {
  const n = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^(?:async\\s+)?function\\s+${n}\\s*\\(|^(?:const|let|var)\\s+${n}\\s*=`);
}

/**
 * Devuelve el texto fuente de una declaración de nivel superior.
 * @param {string} name  Nombre exacto (p. ej. "getPoints", "POINT_TABLE")
 */
export async function extract(name) {
  const ls = await lines();
  const re = startPattern(name);

  const starts = [];
  for (let i = 0; i < ls.length; i++) if (re.test(ls[i])) starts.push(i);

  if (starts.length === 0) {
    throw new Error(
      `extract("${name}"): no se encontró una declaración de nivel superior con ese nombre en index.html. ` +
      `¿Se renombró o se movió? Los tests de caracterización dependen de este nombre.`
    );
  }
  if (starts.length > 1) {
    throw new Error(
      `extract("${name}"): hay ${starts.length} declaraciones con ese nombre ` +
      `(líneas ${starts.map(i => i + 1).join(', ')}). Ambiguo — revisa index.html.`
    );
  }

  const start = starts[0];
  for (let i = start + 1; i < ls.length; i++) {
    if (CLOSER.test(ls[i])) {
      return { name, source: ls.slice(start, i + 1).join('\n'), line: start + 1 };
    }
  }
  throw new Error(`extract("${name}"): no se encontró el cierre en columna 0 desde la línea ${start + 1}.`);
}

/** Extrae varias declaraciones y las concatena en orden. */
export async function extractAll(names) {
  const out = [];
  for (const n of names) out.push(await extract(n));
  return out;
}
