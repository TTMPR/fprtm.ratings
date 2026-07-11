#!/usr/bin/env node
/**
 * FPTM · Fase 3.4 — Export semanal de las tablas críticas.
 *
 * Exporta cada tabla a JSON (fidelidad completa) y CSV (lectura humana),
 * y opcionalmente las sube a un bucket PRIVADO de Supabase Storage.
 *
 * ⚠️  Los exports contienen datos personales (emails, DOB, direcciones).
 *     NUNCA subirlos a este repo (es público) ni a artifacts de Actions
 *     (en repos públicos cualquiera puede descargarlos). Por eso el destino
 *     es un bucket privado de Storage del mismo proyecto Supabase.
 *
 * Uso:
 *   SUPABASE_URL=https://xxxx.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=eyJ... \
 *   BACKUP_UPLOAD=1 node backup/export_backup.mjs
 *
 * Variables:
 *   SUPABASE_URL               URL del proyecto (obligatoria)
 *   SUPABASE_SERVICE_ROLE_KEY  Service role key — Settings → API (obligatoria;
 *                              la anon key NO sirve: no ve tablas con RLS)
 *   BACKUP_UPLOAD=1            Subir al bucket privado (si no, solo local)
 *   BACKUP_BUCKET              Nombre del bucket (default: backups)
 *   OUT_DIR                    Carpeta local de salida (default: ./backup-out)
 */

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const URL_BASE = process.env.SUPABASE_URL;
const KEY      = process.env.SUPABASE_SERVICE_ROLE_KEY;
const UPLOAD   = process.env.BACKUP_UPLOAD === '1';
const BUCKET   = process.env.BACKUP_BUCKET || 'backups';
const OUT_DIR  = process.env.OUT_DIR || './backup-out';

if (!URL_BASE || !KEY) {
  console.error('Faltan SUPABASE_URL y/o SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

// Tablas críticas. Las que no existan en el proyecto se saltan con un aviso.
const TABLES = [
  'Base de Datos',
  'jugadores',
  'torneos',
  'partidos',
  'resultados_evento',
  'insc_registro',
  'membership_requests',
  'photo_requests',
  'club_change_requests',
  'club_info_requests',
  'clubs',
  'articulos',
  'app_settings',
  'player_reg_submissions',
  'player_reg_tokens',
  'resultados_draft',
  'audit_log',
];

const HEADERS = { apikey: KEY, Authorization: `Bearer ${KEY}` };
const PAGE = 1000; // límite por request de PostgREST

async function fetchTable(table) {
  const rows = [];
  for (let from = 0; ; from += PAGE) {
    const res = await fetch(
      `${URL_BASE}/rest/v1/${encodeURIComponent(table)}?select=*`,
      { headers: { ...HEADERS, Range: `${from}-${from + PAGE - 1}`, 'Range-Unit': 'items', Prefer: 'count=exact' } }
    );
    if (res.status === 404) return null; // tabla no existe
    if (!res.ok && res.status !== 416) throw new Error(`${table}: HTTP ${res.status} — ${await res.text()}`);
    if (res.status === 416) break; // rango fuera de la tabla (vacía o fin)
    const batch = await res.json();
    rows.push(...batch);
    if (batch.length < PAGE) break;
  }
  return rows;
}

function toCSV(rows) {
  if (!rows.length) return '';
  const cols = [...new Set(rows.flatMap(r => Object.keys(r)))];
  const esc = v => {
    if (v === null || v === undefined) return '';
    const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [cols.join(','), ...rows.map(r => cols.map(c => esc(r[c])).join(','))].join('\n');
}

async function ensureBucket() {
  const res = await fetch(`${URL_BASE}/storage/v1/bucket`, {
    method: 'POST',
    headers: { ...HEADERS, 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: BUCKET, name: BUCKET, public: false }),
  });
  if (!res.ok && res.status !== 409) { // 409 = ya existe
    const txt = await res.text();
    if (!/already exists|Duplicate/i.test(txt)) throw new Error(`No se pudo crear el bucket: ${txt}`);
  }
}

async function uploadFile(remotePath, contents, contentType) {
  const res = await fetch(`${URL_BASE}/storage/v1/object/${BUCKET}/${remotePath}`, {
    method: 'POST',
    headers: { ...HEADERS, 'Content-Type': contentType, 'x-upsert': 'true' },
    body: contents,
  });
  if (!res.ok) throw new Error(`Upload ${remotePath}: HTTP ${res.status} — ${await res.text()}`);
}

const stamp = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
const localDir = path.join(OUT_DIR, stamp);
await mkdir(localDir, { recursive: true });
if (UPLOAD) await ensureBucket();

const summary = [];
for (const table of TABLES) {
  try {
    const rows = await fetchTable(table);
    if (rows === null) { summary.push(`⤳ ${table}: no existe (saltada)`); continue; }
    const safe = table.replace(/\s+/g, '_');
    const json = JSON.stringify(rows, null, 1);
    const csv  = toCSV(rows);
    await writeFile(path.join(localDir, `${safe}.json`), json);
    await writeFile(path.join(localDir, `${safe}.csv`), csv);
    if (UPLOAD) {
      await uploadFile(`${stamp}/${safe}.json`, json, 'application/json');
      await uploadFile(`${stamp}/${safe}.csv`, csv, 'text/csv');
    }
    summary.push(`✓ ${table}: ${rows.length} filas`);
  } catch (e) {
    summary.push(`✗ ${table}: ${e.message}`);
    process.exitCode = 1;
  }
}

const report = `Backup FPTM ${stamp}\n${summary.join('\n')}\n`;
await writeFile(path.join(localDir, '_resumen.txt'), report);
if (UPLOAD) await uploadFile(`${stamp}/_resumen.txt`, report, 'text/plain');
console.log(report);
console.log(UPLOAD ? `Subido a Storage: bucket "${BUCKET}" → carpeta ${stamp}/` : `Solo local: ${localDir}`);
