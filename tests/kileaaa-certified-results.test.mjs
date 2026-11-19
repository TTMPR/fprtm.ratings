import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { loadPipeline } from './harness/sandbox.mjs';
import {
  CertifiedResultsError, validateKileaaaCertifiedResults,
  previewKileaaaRatingChanges, assessKileaaaReplay,
} from '../integrations/kileaaa/certified-results.mjs';

// All names, Member IDs and results in this suite are invented QA fixtures.
// The rating algorithm is injected from index.html using the official harness.
const official = await loadPipeline();
const roster = [
  { memberId: '10001', rating: 1500 },
  { memberId: '10002', rating: 1400 },
  { memberId: '10003', rating: 1600 },
  { memberId: '10004', rating: 0 },
];

const sets = [
  { player1: 11, player2: 8 },
  { player1: 11, player2: 6 },
  { player1: 11, player2: 9 },
];
const match = (id, p1, p2, winner, outcome, score = []) => ({
  matchId: id,
  categoryId: 'OPEN',
  stage: 'group',
  round: null,
  groupId: 'group-1',
  player1MemberId: p1,
  player2MemberId: p2,
  player1PartnerMemberId: null,
  player2PartnerMemberId: null,
  winnerMemberId: winner,
  outcome,
  sets: score,
});

function pkgPayload() {
  const doubles = match('m5', '10001', '10002', '10001', 'doubles', structuredClone(sets));
  doubles.player1PartnerMemberId = '10003';
  doubles.player2PartnerMemberId = '10004';
  return {
    schemaVersion: 'kileaaa-certified-results-v1',
    destination: 'ratings.ttmpr.xyz',
    source: 'kileaaa',
    tournament: {
      id: 'fictional-2026',
      name: 'Torneo de prueba sin datos reales',
      date: '2026-11-19',
      location: 'Cancha de ensayo',
      resultsFingerprint: 'a'.repeat(64),
      officialEvent: true,
    },
    ratingCalculated: false,
    ratingPublished: false,
    matches: [
      match('m0', '10001', '10002', '10001', 'played', structuredClone(sets)),
      match('m1', '10002', '10003', '10003', 'default'),
      match('m2', '10004', '10002', '10004', 'walkover'),
      match('m3', '10003', '10004', '10004', 'retired', [{player1: 11, player2: 8}]),
      match('m4', '10001', null, '10001', 'bye'),
      doubles,
    ],
  };
}

function sign(payload) {
  const digest = createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  return { ...payload, integrity: { algorithm: 'SHA-256', digest } };
}
const valid = () => sign(pkgPayload());
function errorCode(fn, code) {
  assert.throws(fn, e => {
    assert.ok(e instanceof CertifiedResultsError);
    assert.equal(e.code, code);
    return true;
  });
}

test('accepts exact versioned Kileaaa result contract without connecting to Supabase', () => {
  const payload = valid();
  const parsed = validateKileaaaCertifiedResults(JSON.stringify(payload));
  assert.equal(parsed.importStatus, 'validation_only');
  assert.equal(parsed.publicationAuthorized, false);
  assert.deepEqual(parsed.playerMemberIds, ['10001','10002','10003','10004']);
  assert.equal(parsed.matches.length, 6);
  assert.equal(parsed.ratingCalculated, false);
  assert.equal(parsed.ratingPublished, false);
});

test('read-only preview uses EXACT official getPoints from index.html, not a duplicate formula', () => {
  const v = validateKileaaaCertifiedResults(valid());
  const p = previewKileaaaRatingChanges(v, roster, official.ctx.getPoints);
  assert.equal(p.status, 'preview_only');
  assert.equal(p.officialRatingPublished, false);
  assert.equal(p.requiresIndependentFederationApproval, true);
  assert.equal(p.totalChange, 0);
  assert.equal(p.ratedMatches, 2);
  assert.deepEqual(p.skipped, { bye: 1, walkover: 1, retired: 1, doubles: 1 });
  const changes = Object.fromEntries(p.athletes.map(x => [x.memberId, x.cambioPropuesto]));
  assert.deepEqual(changes, { 10001: 3, 10002: -4, 10003: 1, 10004: 0 });
  assert.equal(p.athletes.find(x=>x.memberId === '10004').ratingInicial, 0);
  assert.equal(p.athletes.find(x=>x.memberId === '10002').ratingPropuesto, 1396);
});

test('checksum mismatch prevents accidental or hostile alteration of approved content', () => {
  const v = valid();
  v.matches[0].winnerMemberId = '10002';
  errorCode(() => validateKileaaaCertifiedResults(v), 'DIGEST_MISMATCH');
});

test('recomputing a SHA-256 hash does not grant publication authorization', () => {
  const v = pkgPayload();
  v.tournament.name = 'Changed by arbitrary sender';
  const checked = validateKileaaaCertifiedResults(sign(v));
  assert.equal(checked.publicationAuthorized, false);
  assert.equal(assessKileaaaReplay(checked).publicationAuthorized, false);
});

test('rejects unknown top-level, tournament, result, and set keys', () => {
  for (const mutate of [
    p => { p.admin = true; },
    p => { p.tournament.ownerUid = 'secret'; },
    p => { p.matches[0].ratingDelta = 200; },
    p => { p.matches[0].sets[0].privateNote = 'a'; },
  ]) {
    const p = pkgPayload();
    mutate(p);
    errorCode(() => validateKileaaaCertifiedResults(sign(p)), 'UNKNOWN_FIELDS');
  }
});

test('rejects wrong origin, schema, authority, flags and nonofficial tournaments', () => {
  for (const mutate of [
    p => { p.source = 'third-party'; },
    p => { p.schemaVersion = 'kileaaa-certified-results-v2'; },
    p => { p.destination = 'other.example'; },
    p => { p.ratingCalculated = true; },
    p => { p.ratingPublished = true; },
  ]) {
    const p = pkgPayload();
    mutate(p);
    errorCode(() => validateKileaaaCertifiedResults(sign(p)), 'WRONG_CONTRACT');
  }
  const p = pkgPayload();
  p.tournament.officialEvent = false;
  errorCode(() => validateKileaaaCertifiedResults(sign(p)), 'UNAPPROVED_RESULTS');
});

test('date is required for official publication and must be real', () => {
  for (const date of [null, '', '2026-02-30', '11/19/2026', '2026-13-02', '2026-1-9']) {
    const p = pkgPayload();
    p.tournament.date = date;
    assert.throws(() => validateKileaaaCertifiedResults(sign(p)));
  }
});

test('rejects duplicate and out-of-order matches, extra matches and oversized input', () => {
  const p = pkgPayload();
  p.matches[1].matchId = 'm0';
  errorCode(() => validateKileaaaCertifiedResults(sign(p)), 'DUPLICATE_MATCH');
  const reversed = pkgPayload();
  reversed.matches.reverse();
  errorCode(() => validateKileaaaCertifiedResults(sign(reversed)), 'OUT_OF_ORDER');
  errorCode(() => validateKileaaaCertifiedResults(valid(), { maxMatches: 2 }), 'INVALID_MATCH_COUNT');
  errorCode(() => validateKileaaaCertifiedResults(JSON.stringify(valid()), { maxBytes: 1024 }),
    'OVERSIZED_PACKAGE');
});

test('rejects invalid Member IDs, duplicate athletes in singles, invalid winner', () => {
  for (const mutate of [
    p => { p.matches[0].player1MemberId = '00001'; },
    p => { p.matches[0].player2MemberId = '10001'; },
    p => { p.matches[0].winnerMemberId = '10004'; },
    p => { p.matches[0].player1MemberId = null; },
  ]) {
    const p = pkgPayload();
    mutate(p);
    assert.throws(() => validateKileaaaCertifiedResults(sign(p)));
  }
});

test('rejects result scores that disagree with certified winner or have invalid sets', () => {
  for (const mutate of [
    p => { p.matches[0].sets[1].player1 = 4; p.matches[0].sets[2].player1 = 4; },
    p => { p.matches[0].sets = []; },
    p => { p.matches[0].sets[0].player2 = 11; },
    p => { p.matches[0].sets[0].player2 = -1; },
    p => { p.matches[0].sets[0].player2 = 250; },
  ]) {
    const p = pkgPayload();
    mutate(p);
    assert.throws(() => validateKileaaaCertifiedResults(sign(p)));
  }
});

test('BYE must have one athlete and no score; doubles must have four distinct athletes', () => {
  for (const mutate of [
    p => { p.matches[4].player2MemberId = '10002'; },
    p => { p.matches[4].sets = structuredClone(sets); },
    p => { p.matches[5].player2PartnerMemberId = null; },
    p => { p.matches[5].player1PartnerMemberId = '10002'; },
    p => { p.matches[0].player1PartnerMemberId = '10003'; },
  ]) {
    const p = pkgPayload();
    mutate(p);
    assert.throws(() => validateKileaaaCertifiedResults(sign(p)));
  }
});

test('unknown roster Member IDs, duplicate roster rows, and invalid official ratings fail closed', () => {
  const checked = validateKileaaaCertifiedResults(valid());
  errorCode(() => previewKileaaaRatingChanges(checked, roster.slice(0,3), official.ctx.getPoints),
    'UNKNOWN_MEMBER');
  errorCode(() => previewKileaaaRatingChanges(checked, [...roster, roster[0]], official.ctx.getPoints),
    'DUPLICATE_ROSTER');
  errorCode(() => previewKileaaaRatingChanges(checked,
    roster.map(row => row.memberId === '10002' ? { ...row, rating: 1500.5 } : row),
    official.ctx.getPoints), 'INVALID_RATING');
});

test('does not accept arithmetic supplied by client instead of official getPoints', () => {
  const checked = validateKileaaaCertifiedResults(valid());
  errorCode(() => previewKileaaaRatingChanges(checked, roster, () => ({aGain:100, bGain:100})),
    'OFFICIAL_ENGINE_ERROR');
});

test('replay classification requires independent recorded fingerprint and digest', () => {
  const checked = validateKileaaaCertifiedResults(valid());
  assert.equal(assessKileaaaReplay(checked).status, 'new');
  const receipt = {
    sourceTournamentId: checked.tournament.id,
    resultsFingerprint: checked.tournament.resultsFingerprint,
    packageDigest: checked.integrity.digest,
  };
  assert.equal(assessKileaaaReplay(checked, receipt).status, 'already_seen');
  assert.equal(assessKileaaaReplay(checked,
    { ...receipt, resultsFingerprint: 'f'.repeat(64) }).status,
    'revision_requires_manual_review');
  assert.equal(assessKileaaaReplay(checked,
    { ...receipt, packageDigest: 'f'.repeat(64) }).status,
    'revision_requires_manual_review');
  errorCode(() => assessKileaaaReplay(checked,
    { ...receipt, sourceTournamentId: 'different' }), 'LEDGER_CONFLICT');
});

test('validated package and nested matches cannot be mutated before federation preview', () => {
  const checked = validateKileaaaCertifiedResults(valid());
  assert.ok(Object.isFrozen(checked));
  assert.ok(Object.isFrozen(checked.tournament));
  assert.ok(Object.isFrozen(checked.matches[0].sets[0]));
  assert.throws(() => { checked.matches[0].winnerMemberId = '10002'; }, TypeError);
  assert.throws(() => { checked.matches.push({}); }, TypeError);
  assert.equal(previewKileaaaRatingChanges(checked, roster, official.ctx.getPoints).ratedMatches, 2);
});

test('engine preview cannot operate with raw unvalidated input', () => {
  errorCode(() => previewKileaaaRatingChanges(valid(), roster, official.ctx.getPoints),
    'UNVERIFIED_INPUT');
});
