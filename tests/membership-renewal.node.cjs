const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const membershipHtml = fs.readFileSync('membresia.html', 'utf8');
const config = fs.readFileSync('membership-config.js', 'utf8');
const migration = fs.readFileSync('sql/api_busqueda_membresia_todos_jugadores.sql', 'utf8');

test('membership form inline JavaScript parses correctly', () => {
  const scripts = [...membershipHtml.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
  assert.equal(scripts.length, 1);
  assert.doesNotThrow(() => new Function(scripts[0][1]));
});

test('renewal searches all canonical Member IDs and does not depend on legacy app', () => {
  assert.match(membershipHtml, /rest\/v1\/api_busqueda_membresia/);
  assert.match(membershipHtml, /member_id_text/);
  assert.match(membershipHtml, /nombre_busqueda/);
  assert.match(membershipHtml, /findExactOfficialPlayer/);
  assert.doesNotMatch(membershipHtml, /fetch\(['"]legacy\.html['"]/);
  assert.doesNotMatch(membershipHtml, /rest\/v1\/api_jugadores/);
  assert.match(config, /supabasePublishableKey/);
});

test('database directory minimizes personal data and prevents reused member IDs', () => {
  assert.match(migration, /security_invoker=true/);
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS base_member_id_unique_idx/);
  const fields = migration.match(/RETURNS TABLE \(([\s\S]*?)\)\s*LANGUAGE sql/);
  assert.ok(fields, 'typed, limited return columns are required');
  assert.doesNotMatch(fields[1], /\bemail\b|address|date_of_birth|phone|guardian/i);
});
