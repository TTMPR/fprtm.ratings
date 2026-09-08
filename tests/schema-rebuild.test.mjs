/**
 * FPTM · Fase 1.0 — Paridad del esquema canónico contra PostgreSQL real
 *
 * Reconstruye `sql/schema/` desde una base VACÍA y comprueba tres cosas que
 * una revisión a ojo no puede garantizar:
 *
 *   1. Paridad de inventario. No un recuento, sino los NOMBRES exactos de las
 *      22 tablas, 7 vistas y 23 funciones que la extracción de sólo lectura
 *      del catálogo de producción (2026-09-08) reportó. Un recuento correcto
 *      con un nombre distinto pasaría desapercibido; una lista, no.
 *
 *   2. Comportamiento de `ensure_rls`. No que el event trigger exista —eso es
 *      trivial— sino que HAGA lo que hace en producción: se crea una tabla de
 *      usar y tirar en `public` y se comprueba que nació con RLS activo sin
 *      que nadie lo pidiera.
 *
 *   3. Idempotencia. La segunda pasada completa sobre la misma base no falla
 *      y no cambia el inventario.
 *
 * Lo que NO cubre: el fichero 090 (políticas RLS) y el 100 (Storage) no están
 * en este repositorio, así que aquí se verifica que RLS está ACTIVO en las 22
 * tablas, no qué políticas tienen. Y `storage` es de Supabase: no existe en
 * un Postgres local.
 *
 * Requiere un PostgreSQL local en /tmp/pg-phase10. Si no está, los tests se
 * saltan en vez de fallar: son de infraestructura, no del pipeline oficial.
 * Ver tests/README.md.
 *
 * NUNCA toca producción. No hay red.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const run = promisify(execFile);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SOCK = '/tmp/pg-phase10';
const PORT = 55432;
const BIN = '/usr/lib/postgresql/16/bin';
const DB = 'schema_rebuild_test';

const disponible = existsSync(`${SOCK}/pgdata`) && existsSync(`${BIN}/psql`);
const saltar = { skip: disponible ? false : 'sin PostgreSQL local en /tmp/pg-phase10' };

/**
 * Inventario de producción, copiado literalmente del resultado de la tercera
 * extracción de sólo lectura. Es la referencia: si el esquema canónico deja
 * de coincidir con esta lista, o el esquema cambió o producción cambió, y en
 * cualquiera de los dos casos hay que enterarse.
 */
const PROD_TABLAS = [
  'Base de Datos', 'app_settings', 'articulos', 'audit_log',
  'club_change_requests', 'club_info_requests', 'clubs', 'historial_rating',
  'insc_busca_companero', 'insc_divisiones', 'insc_equipos', 'insc_registro',
  'jugadores', 'membership_requests', 'miembros', 'partidos', 'photo_requests',
  'player_reg_submissions', 'player_reg_tokens', 'resultados_draft',
  'resultados_evento', 'torneos',
];

const PROD_VISTAS = [
  'api_clubes', 'api_jugadores', 'api_torneos', 'insc_busca_companero_publico',
  'insc_equipos_cupos', 'insc_equipos_publico', 'miembros_alertas',
];

const PROD_FUNCIONES = [
  'editar_equipo', 'fn_audit', 'fprtm_parse_fecha', 'insc_busca_touch',
  'insc_dob_a_fecha', 'insc_equipo_activo', 'insc_equipo_ocupa_cupo',
  'insc_equipos_liberar', 'insc_equipos_reserva_horas', 'insc_equipos_touch',
  'insc_es_menor', 'insc_nombre_norm', 'insc_rating_federativo',
  'inscribir_equipo', 'liberar_cupo_con_credito', 'nombrar_companero',
  'publicar_busca_companero', 'purge_deleted_torneos', 'reservar_cupo_solo',
  'resolver_revision_tecnica', 'retirar_busca_companero', 'rls_auto_enable',
  'update_updated_at',
];

/** Ficheros del esquema canónico que se pueden aplicar en un Postgres normal. */
const FICHEROS = [
  '010_core_tables', '015_miembros_historial', '020_core_alterations',
  '030_registration', '040_content', '050_membership', '060_copa_olimpica',
  '070_functions_triggers', '080_views',
];

const psql = async (sqlText) => {
  const { stdout } = await run(`${BIN}/psql`,
    ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', '-d', DB,
     '-v', 'ON_ERROR_STOP=1', '-tAq', '-c', sqlText]);
  return stdout.trim();
};

const aplicarEsquema = () => Promise.all([]).then(async () => {
  for (const f of FICHEROS) {
    await run(`${BIN}/psql`,
      ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', '-d', DB,
       '-v', 'ON_ERROR_STOP=1', '-q', '-f', `${ROOT}/sql/schema/${f}.sql`]);
  }
});

const lista = async (sqlText) => (await psql(sqlText)).split('\n').filter(Boolean);

/**
 * Preparación a nivel de módulo, no en un hook `before`: con hooks, node:test
 * cierra cada suite antes de que sus tests lleguen a correr.
 */
let primeraPasada = null;
let segundaPasada = null;

if (disponible) {
  await run(`${BIN}/dropdb`, ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', '--if-exists', DB]);
  await run(`${BIN}/createdb`, ['-h', SOCK, '-p', String(PORT), '-U', 'postgres', DB]);

  /*
   * Lo mínimo de Supabase y de pg_cron que el esquema necesita para aplicarse.
   *
   * Se hace con stubs y no recortando los ficheros: así se aplica el 070
   * ENTERO, tal cual está en el repositorio. Un recorte probaría un fichero
   * que nadie va a ejecutar.
   *
   * `cron.job` vive en el esquema `cron`, no en `public`, así que no ensucia
   * el inventario que se compara luego.
   */
  await psql(`
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE OR REPLACE FUNCTION auth.jwt()  RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
    CREATE OR REPLACE FUNCTION auth.uid()  RETURNS uuid  LANGUAGE sql STABLE AS $$ SELECT NULL::uuid $$;
    CREATE OR REPLACE FUNCTION auth.role() RETURNS text  LANGUAGE sql STABLE AS $$ SELECT 'anon'::text $$;
    DO $r$ BEGIN CREATE ROLE anon;          EXCEPTION WHEN duplicate_object THEN NULL; END $r$;
    DO $r$ BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END $r$;
    DO $r$ BEGIN CREATE ROLE service_role;  EXCEPTION WHEN duplicate_object THEN NULL; END $r$;

    CREATE SCHEMA IF NOT EXISTS cron;
    CREATE TABLE IF NOT EXISTS cron.job (
      jobid bigserial PRIMARY KEY, jobname text, schedule text, command text);
    CREATE OR REPLACE FUNCTION cron.schedule(text, text, text) RETURNS bigint
      LANGUAGE sql AS $$ INSERT INTO cron.job (jobname, schedule, command)
                         VALUES ($1, $2, $3) RETURNING jobid $$;
    CREATE OR REPLACE FUNCTION cron.unschedule(text) RETURNS boolean
      LANGUAGE sql AS $$ DELETE FROM cron.job WHERE jobname = $1 RETURNING true $$;`);

  await aplicarEsquema();

  primeraPasada = {
    tablas:    await lista(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                            WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY c.relname`),
    vistas:    await lista(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                            WHERE n.nspname = 'public' AND c.relkind IN ('v','m') ORDER BY c.relname`),
    funciones: await lista(`SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                            WHERE n.nspname = 'public' ORDER BY p.proname`),
  };
}

describe('Esquema canónico · paridad con el inventario de producción', () => {

  test('las 22 tablas de producción, con sus nombres exactos', saltar, () => {
    assert.deepEqual(primeraPasada.tablas, PROD_TABLAS);
  });

  test('las 7 vistas de producción, con sus nombres exactos', saltar, () => {
    assert.deepEqual(primeraPasada.vistas, PROD_VISTAS);
  });

  test('las 23 funciones de producción, con sus nombres exactos', saltar, () => {
    assert.deepEqual(primeraPasada.funciones, PROD_FUNCIONES);
  });

  test('RLS activo en las 22 tablas', saltar, async () => {
    const sinRls = await lista(
      `SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity
       ORDER BY c.relname`);
    assert.deepEqual(sinRls, [], 'hay tablas sin RLS');
  });

  test('todas las vistas resuelven', saltar, async () => {
    // Una vista puede crearse y luego romperse si cambia lo que consulta.
    // Un SELECT ... LIMIT 0 la planifica sin traer filas.
    for (const v of PROD_VISTAS) {
      await psql(`SELECT * FROM public."${v}" LIMIT 0`);
    }
  });

  test('índices y restricciones se crean sin agujeros', saltar, async () => {
    const [idx, con] = await Promise.all([
      psql(`SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'`),
      psql(`SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
            WHERE n.nspname = 'public'`),
    ]);
    assert.ok(Number(idx) >= 40, `sólo ${idx} índices`);
    assert.ok(Number(con) >= 30, `sólo ${con} restricciones`);
  });
});

describe('Event trigger ensure_rls · comportamiento, no sólo presencia', () => {

  test('existe, habilitado, con el evento y las etiquetas de producción', saltar, async () => {
    const fila = await psql(
      `SELECT evtevent || '|' || evtenabled::text || '|' || array_to_string(evttags, ',')
       FROM pg_event_trigger WHERE evtname = 'ensure_rls'`);
    assert.equal(fila, 'ddl_command_end|O|CREATE TABLE,CREATE TABLE AS,SELECT INTO');
  });

  test('apunta a public.rls_auto_enable', saltar, async () => {
    const fn = await psql(
      `SELECT n.nspname || '.' || p.proname FROM pg_event_trigger et
       JOIN pg_proc p ON p.oid = et.evtfoid
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE et.evtname = 'ensure_rls'`);
    assert.equal(fn, 'public.rls_auto_enable');
  });

  test('una tabla nueva en public nace con RLS activo sin pedirlo', saltar, async () => {
    await psql(`CREATE TABLE public.zz_prueba_rls (id int)`);
    try {
      const rls = await psql(
        `SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname = 'zz_prueba_rls'`);
      assert.equal(rls, 't', 'la tabla nació sin RLS: ensure_rls no actuó');
    } finally {
      await psql(`DROP TABLE IF EXISTS public.zz_prueba_rls`);
    }
  });

  test('la tabla de prueba desaparece y el inventario vuelve a 22', saltar, async () => {
    const n = await psql(
      `SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'r'`);
    assert.equal(n, '22');
  });
});

describe('Esquema canónico · idempotencia', () => {

  test('la segunda pasada completa no falla', saltar, async () => {
    await aplicarEsquema();
    segundaPasada = {
      tablas:    await lista(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                              WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY c.relname`),
      vistas:    await lista(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                              WHERE n.nspname = 'public' AND c.relkind IN ('v','m') ORDER BY c.relname`),
      funciones: await lista(`SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                              WHERE n.nspname = 'public' ORDER BY p.proname`),
    };
  });

  test('y no cambia el inventario', saltar, () => {
    assert.deepEqual(segundaPasada, primeraPasada);
  });

  test('ensure_rls sigue siendo uno solo', saltar, async () => {
    // CREATE EVENT TRIGGER no admite IF NOT EXISTS: si el guardia del 070
    // fallara, la segunda pasada habría reventado antes de llegar aquí.
    const n = await psql(`SELECT count(*) FROM pg_event_trigger WHERE evtname = 'ensure_rls'`);
    assert.equal(n, '1');
  });
});
