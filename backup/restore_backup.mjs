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

// PK por tabla para el upsert (on_conflict). Default: id.
const PK = {
  'Base_de_Datos': 'Member ID',
  'app_settings': 'key',
};

// audit_log tiene la PK generada ALWAYS — se restaura sin la columna id.
const STRIP_ID = new Set(['audit_log']);

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

  const pk = PK[name] || 'id';
  let ok = 0;
  try {
    for (let i = 0; i < rows.length; i += BATCH) {
      const chunk = rows.slice(i, i + BATCH);
      const conflict = STRIP_ID.has(name) ? '' : `?on_conflict=${encodeURIComponent(pk)}`;
      const prefer   = STRIP_ID.has(name) ? 'return=minimal' : 'resolution=merge-duplicates,return=minimal';
      const res = await fetch(`${URL_BASE}/rest/v1/${encodeURIComponent(table)}${conflict}`, {
        method: 'POST',
        headers: { ...HEADERS, Prefer: prefer },
        body: JSON.stringify(chunk),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status} — ${await res.text()}`);
      ok += chunk.length;
    }
    console.log(`✓ ${table}: ${ok}/${rows.length} filas restauradas`);
  } catch (e) {
    console.error(`✗ ${table}: ${e.message}`);
    process.exitCode = 1;
  }
}

console.log('\nVerifica en el proyecto de prueba: conteos por tabla y algunos registros al azar.');
