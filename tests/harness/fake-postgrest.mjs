/**
 * FPTM · Fase 1.0 — PostgREST de mentira, PostgreSQL de verdad
 *
 * backup/restore_backup.mjs habla PostgREST por HTTP. Para probarlo de verdad
 * hace falta algo que traduzca esas peticiones a SQL real contra una base real:
 * un mock que devuelva 200 a todo no probaría nada, y el fallo que buscamos
 * (una columna de on_conflict que no corresponde a ninguna restricción única)
 * sólo lo detecta PostgreSQL.
 *
 * Traduce:
 *   POST /rest/v1/<tabla>?on_conflict=a,b   +  Prefer: resolution=merge-duplicates
 *     → INSERT ... ON CONFLICT (a,b) DO UPDATE SET ...
 *   POST /rest/v1/<tabla>                   (sin on_conflict)
 *     → INSERT ...
 *
 * Reproduce el comportamiento de errores que importa: si las columnas de
 * on_conflict no coinciden con una restricción única, PostgreSQL devuelve
 * 42P10 y PostgREST lo traduce a HTTP 400. Aquí se hace lo mismo.
 *
 * Sólo para tests. No toca ninguna base remota.
 */

import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const PSQL = '/usr/lib/postgresql/16/bin/psql';

const q = id => '"' + String(id).replace(/"/g, '""') + '"';
const lit = v => {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE';
  if (typeof v === 'object') return "'" + JSON.stringify(v).replace(/'/g, "''") + "'::jsonb";
  return "'" + String(v).replace(/'/g, "''") + "'";
};

export async function startFakePostgrest({ socket, port, db, listen = 8899 }) {
  const sql = async text => {
    const { stdout } = await run(PSQL, [
      '-h', socket, '-p', String(port), '-U', 'postgres', '-d', db,
      '-v', 'ON_ERROR_STOP=1', '-tAq', '-c', text,
    ]);
    return stdout;
  };

  const server = createServer((req, res) => {
    let body = '';
    req.on('data', c => { body += c; });
    req.on('end', async () => {
      const url = new URL(req.url, 'http://x');
      const table = decodeURIComponent(url.pathname.replace('/rest/v1/', ''));
      const onConflict = url.searchParams.get('on_conflict');

      let rows;
      try { rows = JSON.parse(body || '[]'); } catch { rows = []; }
      if (!Array.isArray(rows)) rows = [rows];
      if (!rows.length) { res.writeHead(201).end('[]'); return; }

      const cols = [...new Set(rows.flatMap(r => Object.keys(r)))];
      const values = rows
        .map(r => '(' + cols.map(c => lit(r[c])).join(',') + ')')
        .join(',');

      let stmt = `INSERT INTO public.${q(table)} (${cols.map(q).join(',')}) VALUES ${values}`;

      if (onConflict) {
        const targets = onConflict.split(',').map(s => q(s.trim()));
        const updatable = cols.filter(c => !onConflict.split(',').map(s => s.trim()).includes(c));
        stmt += updatable.length
          ? ` ON CONFLICT (${targets.join(',')}) DO UPDATE SET ` +
            updatable.map(c => `${q(c)} = EXCLUDED.${q(c)}`).join(',')
          : ` ON CONFLICT (${targets.join(',')}) DO NOTHING`;
      }

      try {
        await sql(stmt);
        res.writeHead(201, { 'Content-Type': 'application/json' }).end('[]');
      } catch (e) {
        const msg = String(e.stderr || e.message);
        // 42P10 = no hay restricción única que coincida con el on_conflict.
        // Es exactamente el error que PostgREST devuelve como 400.
        const code = /42P10|no unique or exclusion constraint/i.test(msg) ? 400
                   : /cannot insert a non-DEFAULT value|GENERATED ALWAYS/i.test(msg) ? 400
                   : 400;
        res.writeHead(code, { 'Content-Type': 'application/json' })
           .end(JSON.stringify({ message: msg.trim().split('\n')[0] }));
      }
    });
  });

  await new Promise(r => server.listen(listen, r));
  server.unref();
  return {
    url: `http://127.0.0.1:${listen}`,
    sql,
    stop: () => new Promise(r => server.close(r)),
  };
}
