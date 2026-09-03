/**
 * FPTM · Fase 1.0 — Ciclo export → restore contra PostgreSQL real
 *
 * Prueba que el JSON que produce backup/export_backup.mjs puede consumirlo
 * backup/restore_backup.mjs SIN apoyarse en restricciones únicas que no
 * existen en producción.
 *
 * No es un mock: tests/harness/fake-postgrest.mjs traduce las peticiones a
 * SQL real contra una base local levantada con sql/schema/. Un mock que
 * respondiera 200 a todo no detectaría nada — y el fallo que motivó este
 * trabajo (on_conflict sobre una columna sin restricción única) sólo lo
 * detecta PostgreSQL.
 *
 * Requiere un PostgreSQL local en /tmp/pg-phase10. Si no está, los tests se
 * saltan en vez de fallar: son de infraestructura, no del pipeline oficial.
 * Ver tests/README.md.
 *
 * No toca Supabase. No hay red más allá de localhost.
 */

import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { startFakePostgrest } from './harness/fake-postgrest.mjs';

const run = promisify(execFile);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SOCK = '/tmp/pg-phase10';
const PORT = 55432;
const BIN = '/usr/lib/postgresql/16/bin';
const DB = 'restore_test';

const disponible = existsSync(`${SOCK}/pgdata`) && existsSync(`${BIN}/psql`);
const saltar = { skip: disponible ? false : 'sin PostgreSQL local en /tmp/pg-phase10' };

/**
 * Preparación a nivel de módulo, no en un hook `before`: con hooks, node:test
 * cerraba cada suite antes de que sus tests llegaran a correr
 * (`cancelledByParent`). Un await de módulo termina antes de que se registre
 * ninguna suite.
 */
let api = null, tmp = null;

const psql = (db, sqlText) =>
  run(`${BIN}/psql`, ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', '-d', db,
                      '-v', 'ON_ERROR_STOP=1', '-tAq', '-c', sqlText]);

// Levanta una base con el esquema canónico y arranca el PostgREST de mentira.
if (disponible) {
  await run(`${BIN}/dropdb`, ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', '--if-exists', DB]);
  await run(`${BIN}/createdb`, ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', DB]);

  // Mínimo de Supabase que el esquema necesita para aplicarse.
  await psql(DB, `
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE OR REPLACE FUNCTION auth.jwt()  RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
    CREATE OR REPLACE FUNCTION auth.uid()  RETURNS uuid  LANGUAGE sql STABLE AS $$ SELECT NULL::uuid $$;
    CREATE OR REPLACE FUNCTION auth.role() RETURNS text  LANGUAGE sql STABLE AS $$ SELECT 'anon'::text $$;
    DO $r$ BEGIN
      CREATE ROLE anon;          EXCEPTION WHEN duplicate_object THEN NULL; END $r$;
    DO $r$ BEGIN
      CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END $r$;
    DO $r$ BEGIN
      CREATE ROLE service_role;  EXCEPTION WHEN duplicate_object THEN NULL; END $r$;`);

  for (const f of ['010_core_tables', '020_core_alterations', '030_registration',
                   '040_content', '050_membership', '060_copa_olimpica']) {
    await run(`${BIN}/psql`, ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', '-d', DB,
                              '-v', 'ON_ERROR_STOP=1', '-q', '-f', `${ROOT}/sql/schema/${f}.sql`]);
  }

  // audit_log y su trigger viven en 070. Se aplica sin el bloque de pg_cron,
  // que no está instalado en el Postgres de pruebas.
  const f070 = (await readFile(`${ROOT}/sql/schema/070_functions_triggers.sql`, 'utf8'));
  await psql(DB, f070.slice(0, f070.indexOf('SELECT cron.unschedule')));

  // Tablas todavía sin DDL en el repositorio; forma mínima para poder probar
  // que la restauración NO las trata con un on_conflict adivinado.
  await psql(DB, `
    CREATE TABLE IF NOT EXISTS public.historial_rating (id bigserial PRIMARY KEY, nota text);
    CREATE TABLE IF NOT EXISTS public.miembros (id bigserial PRIMARY KEY, nombre_completo text);`);

  api = await startFakePostgrest({ socket: SOCK, port: PORT, db: DB });
  tmp = await mkdtemp(path.join(os.tmpdir(), 'restore-test-'));
}

after(async () => {
  if (api) await api.stop();
  if (tmp) await rm(tmp, { recursive: true, force: true });
});

/**
 * Restaura EXACTAMENTE las tablas que se le pasan, en una carpeta propia.
 * El aislamiento importa: restore_backup.mjs procesa todos los .json de la
 * carpeta, así que compartirla haría que un test arrastrara los datos de otro.
 *
 * @param {Record<string, object[]>} tablas  nombre de fichero → filas
 */
const restaurar = async (tablas) => {
  const dir = await mkdtemp(path.join(tmp, 'lote-'));
  for (const [nombre, filas] of Object.entries(tablas)) {
    await writeFile(path.join(dir, `${nombre}.json`), JSON.stringify(filas, null, 1));
  }
  return run('node', [`${ROOT}/backup/restore_backup.mjs`, dir], {
    env: { ...process.env, TARGET_SUPABASE_URL: api.url, TARGET_SERVICE_ROLE_KEY: 'test' },
  });
};

/** Cuenta filas, opcionalmente filtrando: la base es compartida por todos los tests. */
const cuenta = async (tabla, where = 'true') =>
  Number((await psql(DB, `SELECT count(*) FROM public."${tabla}" WHERE ${where}`)).stdout.trim());

const jugador = (id, rating) => ({
  'Member ID': id, 'First Name': `N${id}`, 'Last Name': `A${id}`, 'Rating': rating,
  'Email': `j${id}@x.test`, 'Sex': 'M', 'Date of Birth': '2000-01-01',
  'Expiration Date': '2027-01-01', 'Home Address': 'calle', 'Club': 'CLUB',
  'New Rating': rating, 'Escuela': null,
});

describe('R1 · "Base de Datos" — la clave de conflicto real', saltar, () => {
  test('restaura con la PK de diez columnas verificada en producción', async () => {
    const { stdout } = await restaurar({ Base_de_Datos: [jugador(1, 1500), jugador(2, 1600)] });
    assert.match(stdout, /✓ Base de Datos: 2\/2/);
    assert.equal(await cuenta('Base de Datos', '"Member ID" IN (1,2)'), 2);
  });

  test('es idempotente mientras no cambie ninguna columna de la clave', async () => {
    const lote = { Base_de_Datos: [jugador(1, 1500), jugador(2, 1600)] };
    await restaurar(lote);
    await restaurar(lote);
    assert.equal(await cuenta('Base de Datos', '"Member ID" IN (1,2)'), 2, 'no debe duplicar');
  });

  test('DEFECTO DEL ESQUEMA · si cambia el rating, inserta otra fila en vez de actualizar', async () => {
    // "Rating" forma parte de la clave primaria, así que la fila con el nuevo
    // rating es una fila distinta a ojos de ON CONFLICT. No es un fallo del
    // script: es la PK de producción. Se fija para que el efecto sea visible.
    await restaurar({ Base_de_Datos: [jugador(1, 1500)] });
    await restaurar({ Base_de_Datos: [jugador(1, 1777)] });
    const n = Number((await psql(DB,
      `SELECT count(*) FROM public."Base de Datos" WHERE "Member ID" = 1`)).stdout.trim());
    assert.equal(n, 2, 'quedan dos filas para el mismo Member ID');
  });

  test('la versión anterior del script habría fallado (on_conflict=Member ID)', async () => {
    // Prueba directa contra PostgreSQL de por qué había que cambiarlo.
    await assert.rejects(
      () => psql(DB, `INSERT INTO public."Base de Datos"
              ("Member ID","First Name","Last Name","Rating","Email","Sex",
               "Date of Birth","Expiration Date","Home Address","Club")
              VALUES (9,'x','y',1,'e','M','d','e','h','c')
              ON CONFLICT ("Member ID") DO NOTHING`),
      /no unique or exclusion constraint/i);
  });
});

describe('R2 · insc_divisiones — clave compuesta (torneo, division)', saltar, () => {
  const div = (torneo, division, precio) => ({
    torneo, division, nombre: `Div ${division}`, precio,
    max_equipos: 20, orden: 1, permite_reserva_solo: false,
  });

  test('restaura usando la clave compuesta', async () => {
    const { stdout } = await restaurar({
      insc_divisiones: [div('copa2026', 'div1', 100), div('copa2026', 'div2', 80)] });
    assert.match(stdout, /✓ insc_divisiones: 2\/2/);
    assert.equal(await cuenta('insc_divisiones', "torneo='copa2026'"), 2);
  });

  test('re-restaurar actualiza en vez de duplicar', async () => {
    await restaurar({ insc_divisiones: [div('copa2026', 'div1', 999)] });
    assert.equal(await cuenta('insc_divisiones', "torneo='copa2026'"), 2,
      'sigue habiendo dos divisiones');
    const precio = (await psql(DB,
      `SELECT precio FROM public.insc_divisiones WHERE torneo='copa2026' AND division='div1'`)).stdout.trim();
    assert.equal(Number(precio), 999, 'el precio se actualizó');
  });
});

describe('R3 · resultados_evento — columna identidad', saltar, () => {
  test('PostgreSQL rechaza un id explícito en una columna GENERATED ALWAYS', async () => {
    await assert.rejects(
      () => psql(DB, `INSERT INTO public.resultados_evento
              (id,id_torneo,id_jugador,nombre,rating_inicio,rating_fin)
              VALUES (1,1,1,'x',1000,1000)`),
      /cannot insert a non-DEFAULT value into column "id"/i);
  });

  test('la restauración descarta el id y funciona', async () => {
    const { stdout } = await restaurar({ resultados_evento: [
      { id: 41, id_torneo: 1, id_jugador: 7, nombre: 'Jugador 7',
        club: 'CLUB', rating_inicio: 1500, rating_fin: 1508, ganados: 2, perdidos: 1 },
    ] });
    assert.match(stdout, /✓ resultados_evento: 1\/1/);
    assert.equal(await cuenta('resultados_evento', 'id_jugador = 7'), 1);
  });

  test('el id se regenera: no conserva el original del backup', async () => {
    const id = (await psql(DB,
      `SELECT id FROM public.resultados_evento WHERE id_jugador = 7`)).stdout.trim();
    assert.notEqual(id, '41', 'el id lo asigna la identidad, no el backup');
  });

  test('COMPORTAMIENTO ELEGIDO · sin id no hay clave, así que NO es idempotente', async () => {
    // Con id descartado no queda ninguna clave por la que hacer merge, y
    // PostgREST no emite OVERRIDING SYSTEM VALUE. La única restauración
    // posible por la API es un INSERT simple. Restaurar siempre en vacío.
    const antes = await cuenta('resultados_evento');  // total, sin filtro
    await restaurar({ resultados_evento: [
      { id: 42, id_torneo: 1, id_jugador: 8, nombre: 'Jugador 8',
        club: 'CLUB', rating_inicio: 1500, rating_fin: 1490, ganados: 0, perdidos: 1 },
    ] });
    assert.equal(await cuenta('resultados_evento'), antes + 1, 'una segunda pasada duplica');
  });

  test('el aviso de no-idempotencia sale por pantalla', async () => {
    const { stdout } = await restaurar({ resultados_evento: [
      { id: 43, id_torneo: 1, id_jugador: 9, nombre: 'Jugador 9',
        club: 'CLUB', rating_inicio: 1400, rating_fin: 1400, ganados: 0, perdidos: 0 },
    ] });
    assert.match(stdout, /resultados_evento.*no idempotente/);
  });
});

describe('R4 · insc_equipos e insc_busca_companero — clave id', saltar, () => {
  test('insc_equipos restaura y es idempotente', async () => {
    const equipo = { id: 1, torneo: 'copa2026', division: 'div1', estado: 'confirmado',
                     cap_member_id: 1, cap_nombre: 'Capitan', cap_rating: 1500 };
    await restaurar({ insc_equipos: [equipo] });
    await restaurar({ insc_equipos: [equipo] });
    assert.equal(await cuenta('insc_equipos', 'id = 1'), 1);
  });

  test('insc_busca_companero restaura y es idempotente', async () => {
    const aviso = { id: 1, torneo: 'copa2026', member_id: 42, estado: 'activo',
                    nombre: 'Jugador Solo', nombre_norm: 'jugador solo',
                    contacto_tipo: 'email', es_menor: false, rating: 1500 };
    await restaurar({ insc_busca_companero: [aviso] });
    await restaurar({ insc_busca_companero: [aviso] });
    assert.equal(await cuenta('insc_busca_companero', 'id = 1'), 1);
  });
});

describe('R5 · audit_log — identidad, igual que resultados_evento', saltar, () => {
  test('restaura descartando el id', async () => {
    const { stdout } = await restaurar({ audit_log: [
      { id: 99, occurred_at: '2026-01-01T00:00:00Z', actor: 'anon',
        action: 'INSERT', table_name: 'torneos', record_id: '1',
        old_data: null, new_data: { nombre: 'X' } },
    ] });
    assert.match(stdout, /✓ audit_log: 1\/1/);
    assert.ok(await cuenta('audit_log', "table_name = 'torneos'") >= 1);
  });
});

describe('R6 · Tablas cuyo DDL aún no se ha extraído', saltar, () => {
  test('historial_rating y miembros se insertan sin on_conflict adivinado', async () => {
    const { stdout } = await restaurar({
      historial_rating: [{ id: 1, nota: 'x' }],
      miembros: [{ id: 1, nombre_completo: 'Persona' }],
    });
    assert.match(stdout, /✓ historial_rating: 1\/1/);
    assert.match(stdout, /✓ miembros: 1\/1/);
    assert.match(stdout, /historial_rating.*no idempotente/);
    assert.match(stdout, /miembros.*no idempotente/);
  });
});

describe('R7 · Ciclo completo', saltar, () => {
  test('ninguna tabla de la restauración depende de una clave inexistente', async () => {
    // Si alguna clave de conflicto no correspondiera a una restricción única
    // real, PostgreSQL devolvería 42P10 y el script marcaría ✗.
    const { stdout } = await restaurar({
      Base_de_Datos:        [jugador(50, 1500)],
      insc_divisiones:      [{ torneo: 'x', division: 'd', nombre: 'D', precio: 10,
                               max_equipos: 4, orden: 1, permite_reserva_solo: false }],
      insc_equipos:         [{ id: 90, torneo: 'x', division: 'd', estado: 'confirmado',
                               cap_member_id: 50, cap_nombre: 'C', cap_rating: 1500 }],
      insc_busca_companero: [{ id: 90, torneo: 'x', member_id: 50, estado: 'activo',
                               nombre: 'N', nombre_norm: 'n', contacto_tipo: 'email',
                               es_menor: false, rating: 1500 }],
      resultados_evento:    [{ id: 900, id_torneo: 1, id_jugador: 50, nombre: 'N',
                               rating_inicio: 1500, rating_fin: 1500 }],
      audit_log:            [{ id: 900, occurred_at: '2026-01-01T00:00:00Z', actor: 'anon',
                               action: 'INSERT', table_name: 'torneos', record_id: '1',
                               old_data: null, new_data: {} }],
    });
    assert.doesNotMatch(stdout, /✗/, `alguna tabla falló:\n${stdout}`);
    assert.doesNotMatch(stdout, /no unique or exclusion constraint/i);
  });
});
