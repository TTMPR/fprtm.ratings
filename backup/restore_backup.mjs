#!/usr/bin/env node
/**
 * FPTM · Fase 3.4 — Restauración de un backup en un proyecto Supabase.
 *
 * "Backup que nunca se ha restaurado = esperanza, no backup."
 * Este script existe para el ejercicio de verificación: restaurar el export
 * en un proyecto Supabase DE PRUEBA y comprobar que los datos están completos.
 *
 * Requisito: el proyecto destino debe tener el MISMO esquema (corre antes
 * los setup_*.sql / create_*.sql de este repo en el proyecto de prueba).
 *
 * Uso:
 *   TARGET_SUPABASE_URL=https://proyecto-prueba.supabase.co \
 *   TARGET_SERVICE_ROLE_KEY=eyJ... \
 *   node backup/restore_backup.mjs ./backup-out/2026-07-11
 *
 * Hace upsert (merge por PK): re-ejecutable sin duplicar filas.
 */

import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

const URL_BASE = process.env.TARGET_SUPABASE_URL;
const KEY      = process.env.TARGET_SERVICE_ROLE_KEY;
const DIR      = process.argv[2];

if (!URL_BASE || !KEY || !DIR) {
  console.error('Uso: TARGET_SUPABASE_URL=... TARGET_SERVICE_ROLE_KEY=... node backup/restore_backup.mjs <carpeta-del-backup>');
  process.exit(1);
}

// ─── Claves de conflicto, verificadas contra producción (2026-09-03) ────────
//
// Estos valores salen de la extracción de sólo lectura del catálogo, no de
// suposiciones. PostgREST exige que las columnas de `on_conflict` correspondan
// a una restricción única real; si no, PostgreSQL responde 42P10 y la
// restauración falla.
//
// ⚠️  "Base de Datos" NO tiene a "Member ID" como clave única. Su PK son diez
//     columnas. La versión anterior de este script usaba on_conflict=Member ID
//     y por tanto la restauración de la tabla más importante del sistema
//     habría fallado siempre. Nunca se había probado.
//
//     Consecuencia de usar la PK real: como incluye "Rating", restaurar una
//     fila cuyo rating cambió NO actualiza la fila existente — inserta otra.
//     Es una limitación del esquema actual, no del script. Corregir la PK es
//     un cambio de producción aparte, con su propio plan.
const PK = {
  'Base_de_Datos': [
    'Member ID', 'First Name', 'Last Name', 'Rating', 'Email',
    'Sex', 'Date of Birth', 'Expiration Date', 'Home Address', 'Club',
  ],
  'app_settings':     ['key'],
  'insc_divisiones':  ['torneo', 'division'],   // PK compuesta
  // El resto usa 'id' (default).
};

// Columnas identidad que PostgreSQL no deja escribir explícitamente.
// Verificado: un INSERT con id explícito en resultados_evento devuelve
// "cannot insert a non-DEFAULT value into column id". Sólo se puede con
// OVERRIDING SYSTEM VALUE, cláusula que PostgREST no emite. Así que la única
// restauración posible por la API es sin la columna id.
const STRIP_ID = new Set(['audit_log', 'resultados_evento']);

// Tablas que se restauran con INSERT simple, sin on_conflict.
//   · audit_log y resultados_evento: se les quita el id, así que no queda
//     ninguna clave por la que hacer merge.
//   · historial_rating y miembros: existen en producción pero su DDL todavía
//     no se ha extraído. Sin conocer su clave real, hacer upsert sería
//     adivinar — y adivinar mal es exactamente el fallo que este cambio
//     corrige. Insertar sin conflicto nunca falla por clave equivocada.
//
// ⚠️  Estas tablas NO son idempotentes al restaurar: re-ejecutar duplica filas.
//     Restaurar siempre sobre una base vacía.
const NO_UPSERT = new Set(['audit_log', 'resultados_evento', 'historial_rating', 'miembros']);

const HEADERS = { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
const BATCH = 500;

const files = (await readdir(DIR)).filter(f => f.endsWith('.json'));
if (!files.length) { console.error(`No hay .json en ${DIR}`); process.exit(1); }

for (const file of files) {
  const name  = path.basename(file, '.json');
  const table = name.replace(/_/g, ' ') === 'Base de Datos' ? 'Base de Datos' : name;
  let rows = JSON.parse(await readFile(path.join(DIR, file), 'utf8'));
  if (!rows.length) { console.log(`⤳ ${table}: vacía`); continue; }
  if (STRIP_ID.has(name)) rows = rows.map(({ id, ...rest }) => rest);

  const pk = PK[name] || ['id'];
  const upsert = !NO_UPSERT.has(name);
  let ok = 0;
  try {
    for (let i = 0; i < rows.length; i += BATCH) {
      const chunk = rows.slice(i, i + BATCH);
      // on_conflict admite varias columnas separadas por coma; cada una se
      // codifica por separado para no romper los nombres con espacios.
      const conflict = upsert
        ? `?on_conflict=${pk.map(encodeURIComponent).join(',')}`
        : '';
      const prefer = upsert
        ? 'resolution=merge-duplicates,return=minimal'
        : 'return=minimal';
      const res = await fetch(`${URL_BASE}/rest/v1/${encodeURIComponent(table)}${conflict}`, {
        method: 'POST',
        headers: { ...HEADERS, Prefer: prefer },
        body: JSON.stringify(chunk),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status} — ${await res.text()}`);
      ok += chunk.length;
    }
    console.log(`✓ ${table}: ${ok}/${rows.length} filas restauradas` +
                (upsert ? '' : '  (insert simple — no idempotente)'));
  } catch (e) {
    console.error(`✗ ${table}: ${e.message}`);
    process.exitCode = 1;
  }
}

console.log('\nVerifica en el proyecto de prueba: conteos por tabla y algunos registros al azar.');
