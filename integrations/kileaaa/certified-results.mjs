/**
 * Kileaaa certified-results import boundary (OFFLINE ONLY).
 *
 * Validates the versioned JSON handoff, checks integrity and compares official
 * Member IDs against a supplied authoritative roster. It contains NO network,
 * storage, authentication, SQL, write, or automatic-publication capability.
 *
 * The SHA-256 digest detects accidental/tampered payload bytes; it does not
 * authenticate the sender. A future server-side FPTM importer MUST independently
 * authenticate an authorized operator, authorize the source and revalidate the
 * roster inside a transaction immediately before publication.
 */
import { createHash } from 'node:crypto';

export class CertifiedResultsError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'CertifiedResultsError';
    this.code = code;
  }
}

function fail(code, message) {
  throw new CertifiedResultsError(code, message);
}

function object(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail('INVALID_SHAPE', label + ' debe ser un objeto JSON');
  }
}

function exactKeys(value, required, label) {
  object(value, label);
  const got = Object.keys(value);
  if (got.length !== required.length || got.some(key => !required.includes(key))) {
    fail('UNKNOWN_FIELDS', label + ' contiene campos inesperados o incompletos');
  }
}

function str(value, label, max = 200, { allowEmpty = false } = {}) {
  if (typeof value !== 'string' || value.length > max || value !== value.trim() ||
      (!allowEmpty && value.length === 0) || /[\u0000-\u001f\u007f]/.test(value)) {
    fail('INVALID_FIELD', label + ' es inválido');
  }
  return value;
}

function nullableStr(value, label, max = 200) {
  return value === null ? null : str(value, label, max);
}

function memberId(value, label) {
  if (typeof value !== 'string' || !/^[1-9][0-9]{0,11}$/.test(value)) {
    fail('INVALID_MEMBER_ID', label + ' no es un Member ID FPTM válido');
  }
  return value;
}

function optionalMemberId(value, label) {
  return value === null ? null : memberId(value, label);
}

function rating(value, label) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 5000) {
    fail('INVALID_RATING', label + ' debe ser un entero entre 0 y 5000');
  }
  return value;
}

function dateOnly(value) {
  const d = str(value, 'Fecha del torneo', 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d) ||
      Number.isNaN(Date.parse(d + 'T00:00:00Z')) ||
      new Date(d + 'T00:00:00Z').toISOString().slice(0, 10) !== d) {
    fail('INVALID_DATE', 'El torneo oficial requiere una fecha YYYY-MM-DD válida');
  }
  return d;
}

const ROOT = [
  'schemaVersion', 'destination', 'source', 'tournament',
  'ratingCalculated', 'ratingPublished', 'matches', 'integrity',
];
const TOURNAMENT = ['id', 'name', 'date', 'location', 'resultsFingerprint', 'officialEvent'];
const MATCH = [
  'matchId', 'categoryId', 'stage', 'round', 'groupId',
  'player1MemberId', 'player2MemberId', 'player1PartnerMemberId',
  'player2PartnerMemberId', 'winnerMemberId', 'outcome', 'sets',
];
const OUTCOMES = new Set(['played', 'default', 'walkover', 'retired', 'doubles', 'bye']);
const RATED_OUTCOMES = new Set(['played', 'default']);
const SET_KEYS = ['player1', 'player2'];

/**
 * Parse the full Kileaaa JSON handoff with a strict, versioned schema.
 *
 * @param {string|object} raw JSON text or JSON-parsed object
 * @param {{maxBytes?:number, maxMatches?:number}} opts
 * @returns {object} immutable data transfer package (not publication approval)
 */
export function validateKileaaaCertifiedResults(raw, opts = {}) {
  const maxBytes = opts.maxBytes ?? 8 * 1024 * 1024;
  const maxMatches = opts.maxMatches ?? 5000;
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1024 ||
      !Number.isSafeInteger(maxMatches) || maxMatches < 1 || maxMatches > 20000) {
    fail('INVALID_OPTIONS', 'Límites de validación inválidos');
  }
  let serialized;
  try {
    serialized = typeof raw === 'string' ? raw : JSON.stringify(raw);
  } catch {
    fail('INVALID_JSON', 'No se pudo serializar el paquete JSON');
  }
  if (typeof serialized !== 'string' || Buffer.byteLength(serialized, 'utf8') > maxBytes) {
    fail('OVERSIZED_PACKAGE', 'El paquete excede el límite permitido');
  }
  let pkg;
  try {
    pkg = JSON.parse(serialized);
  } catch {
    fail('INVALID_JSON', 'El documento no es JSON válido');
  }
  exactKeys(pkg, ROOT, 'Paquete');
  if (pkg.schemaVersion !== 'kileaaa-certified-results-v1' ||
      pkg.destination !== 'ratings.ttmpr.xyz' || pkg.source !== 'kileaaa' ||
      pkg.ratingCalculated !== false || pkg.ratingPublished !== false) {
    fail('WRONG_CONTRACT', 'La versión, autoridad u origen del paquete no coincide');
  }
  exactKeys(pkg.tournament, TOURNAMENT, 'Torneo');
  const tournament = pkg.tournament;
  str(tournament.id, 'ID del torneo', 200);
  str(tournament.name, 'Nombre del torneo', 200);
  // Kileaaa v1 can export a null date for a legacy tournament, but official
  // ingestion must NOT publish a tournament without a valid event date.
  dateOnly(tournament.date);
  if (tournament.location !== null) nullableStr(tournament.location, 'Lugar del torneo', 300);
  if (tournament.officialEvent !== true ||
      typeof tournament.resultsFingerprint !== 'string' ||
      !/^[a-f0-9]{64}$/.test(tournament.resultsFingerprint)) {
    fail('UNAPPROVED_RESULTS', 'Falta huella válida de resultados oficiales certificados');
  }
  if (!Array.isArray(pkg.matches) || pkg.matches.length < 1 ||
      pkg.matches.length > maxMatches) {
    fail('INVALID_MATCH_COUNT', 'Cantidad de partidos fuera de los límites');
  }
  exactKeys(pkg.integrity, ['algorithm', 'digest'], 'Integridad');
  if (pkg.integrity.algorithm !== 'SHA-256' ||
      typeof pkg.integrity.digest !== 'string' ||
      !/^[a-f0-9]{64}$/.test(pkg.integrity.digest)) {
    fail('INVALID_DIGEST', 'Huella SHA-256 inválida');
  }
  const { integrity, ...payload } = pkg;
  const expected = createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  if (integrity.digest !== expected) {
    fail('DIGEST_MISMATCH', 'El archivo fue modificado después de certificarse');
  }
  const seenMatches = new Set();
  let previousId = null;
  const allIds = new Set();
  for (const row of pkg.matches) {
    exactKeys(row, MATCH, 'Partido');
    str(row.matchId, 'ID del partido', 200);
    str(row.categoryId, 'Categoría', 200);
    str(row.stage, 'Fase', 80);
    nullableStr(row.round, 'Ronda', 100);
    nullableStr(row.groupId, 'Grupo', 100);
    if (seenMatches.has(row.matchId)) fail('DUPLICATE_MATCH', 'El lote repite un partido');
    seenMatches.add(row.matchId);
    if (previousId !== null && previousId.localeCompare(row.matchId) >= 0) {
      fail('OUT_OF_ORDER', 'El paquete debe conservar el orden certificado de partidos');
    }
    previousId = row.matchId;
    if (!OUTCOMES.has(row.outcome)) fail('INVALID_OUTCOME', 'Resultado no reconocido');
    for (const key of [
      'player1MemberId', 'player2MemberId', 'player1PartnerMemberId',
      'player2PartnerMemberId', 'winnerMemberId',
    ]) {
      optionalMemberId(row[key], key);
      if (row[key]) allIds.add(row[key]);
    }
    const p1 = row.player1MemberId;
    const p2 = row.player2MemberId;
    const winner = row.winnerMemberId;
    if (!p1) fail('MISSING_PLAYER', 'Todo partido debe identificar al primer atleta');
    if (row.outcome === 'bye') {
      if (p2 !== null || winner !== p1 || row.player1PartnerMemberId !== null ||
          row.player2PartnerMemberId !== null) {
        fail('INVALID_BYE', 'BYE no puede contener adversario ni parejas');
      }
    } else if (!p2 || p1 === p2 || (winner !== p1 && winner !== p2)) {
      fail('INVALID_RESULT', 'Participantes y ganador incompatibles');
    }
    if (row.outcome === 'doubles') {
      const ids = [p1, p2, row.player1PartnerMemberId, row.player2PartnerMemberId];
      if (ids.some(id => id === null) || new Set(ids).size !== 4) {
        fail('INVALID_DOUBLES', 'Dobles requiere cuatro Member IDs distintos');
      }
    } else if (row.player1PartnerMemberId !== null || row.player2PartnerMemberId !== null) {
      fail('INVALID_PARTNERS', 'Solo dobles puede incluir parejas');
    }
    if (!Array.isArray(row.sets) || row.sets.length > 7) {
      fail('INVALID_SETS', 'Partido contiene demasiados sets o un formato inválido');
    }
    let firstWins = 0;
    let secondWins = 0;
    for (const set of row.sets) {
      exactKeys(set, SET_KEYS, 'Set');
      if (!Number.isSafeInteger(set.player1) || !Number.isSafeInteger(set.player2) ||
          set.player1 < 0 || set.player2 < 0 || set.player1 > 99 || set.player2 > 99 ||
          set.player1 === set.player2) {
        fail('INVALID_SETS', 'Marcador de set inválido');
      }
      if (set.player1 > set.player2) firstWins++;
      else secondWins++;
    }
    if (row.outcome === 'bye' && row.sets.length !== 0) {
      fail('INVALID_BYE', 'BYE no tiene sets jugados');
    }
    if (row.outcome === 'played' || row.outcome === 'doubles') {
      if (row.sets.length < 3 ||
          (firstWins === secondWins) ||
          (firstWins > secondWins ? p1 : p2) !== winner) {
        fail('INVALID_SETS', 'El ganador no coincide con los sets certificados');
      }
    }
  }
  // The package was validated, NOT authenticated: any actor can construct a
  // self-consistent SHA-256 digest. A protected FPTM endpoint must verify who
  // supplied it and whether these are genuinely approved Kileaaa results.
  return { ...pkg, playerMemberIds: [...allIds].sort((a, b) => Number(a) - Number(b)),
    importStatus: 'validation_only', publicationAuthorized: false };
}

/**
 * Offline read-only comparison against canonical roster rows supplied by the
 * FPTM authority. Official point math is injected from index.html getPoints.
 * This method can never commit a rating, create a tournament, or publish.
 */
export function previewKileaaaRatingChanges(validated, officialRoster, officialGetPoints) {
  if (validated?.importStatus !== 'validation_only' ||
      validated?.publicationAuthorized !== false ||
      typeof officialGetPoints !== 'function' || !Array.isArray(officialRoster)) {
    fail('UNVERIFIED_INPUT', 'Verifica paquete, padrón y función oficial antes de comparar');
  }
  const roster = new Map();
  for (const row of officialRoster) {
    object(row, 'Atleta del padrón');
    const id = memberId(row.memberId, 'Padrón Member ID');
    if (roster.has(id)) fail('DUPLICATE_ROSTER', 'Member ID duplicado en el padrón oficial');
    roster.set(id, rating(row.rating, 'Rating oficial'));
  }
  for (const id of validated.playerMemberIds) {
    if (!roster.has(id)) fail('UNKNOWN_MEMBER', 'Un Member ID no aparece en el padrón oficial: ' + id);
  }
  const deltaByPlayer = new Map(validated.playerMemberIds.map(id => [id, 0]));
  const wins = new Map(validated.playerMemberIds.map(id => [id, 0]));
  const losses = new Map(validated.playerMemberIds.map(id => [id, 0]));
  let ratedMatches = 0;
  const skipped = { bye: 0, walkover: 0, retired: 0, doubles: 0 };
  for (const match of validated.matches) {
    if (!RATED_OUTCOMES.has(match.outcome)) {
      skipped[match.outcome]++;
      continue;
    }
    const p1 = match.player1MemberId;
    const p2 = match.player2MemberId;
    const win1 = match.winnerMemberId === p1;
    const points = officialGetPoints(roster.get(p1), roster.get(p2), win1);
    if (!points || !Number.isSafeInteger(points.aGain) ||
        !Number.isSafeInteger(points.bGain) || points.aGain + points.bGain !== 0 ||
        (win1 && points.aGain < 0) || (!win1 && points.bGain < 0)) {
      fail('OFFICIAL_ENGINE_ERROR', 'El motor oficial devolvió un cambio inválido');
    }
    deltaByPlayer.set(p1, deltaByPlayer.get(p1) + points.aGain);
    deltaByPlayer.set(p2, deltaByPlayer.get(p2) + points.bGain);
    wins.set(match.winnerMemberId, wins.get(match.winnerMemberId) + 1);
    const loser = win1 ? p2 : p1;
    losses.set(loser, losses.get(loser) + 1);
    ratedMatches++;
  }
  const athletes = validated.playerMemberIds.map(id => {
    const initial = roster.get(id);
    const change = deltaByPlayer.get(id);
    return { memberId: id, ratingInicial: initial, cambioPropuesto: change,
      ratingPropuesto: initial + change, ganados: wins.get(id), perdidos: losses.get(id) };
  });
  if (athletes.some(row => row.ratingPropuesto < 0 || !Number.isSafeInteger(row.ratingPropuesto))) {
    fail('INVALID_FINAL_RATING', 'El rating simulado produce valores fuera de rango');
  }
  const totalChange = athletes.reduce((sum, row) => sum + row.cambioPropuesto, 0);
  if (totalChange !== 0) fail('NON_ZERO_SUM', 'La proyección no conserva la suma cero');
  return {
    sourceTournamentId: validated.tournament.id,
    resultsFingerprint: validated.tournament.resultsFingerprint,
    packageDigest: validated.integrity.digest,
    ratingAuthority: 'ratings.ttmpr.xyz',
    basedOn: 'fptm_official_roster_snapshot',
    status: 'preview_only',
    officialRatingPublished: false,
    requiresIndependentFederationApproval: true,
    ratedMatches, skipped, totalChange, athletes,
  };
}

/**
 * Pure replay policy. Reads an authoritative ledger snapshot provided by a
 * future server handler; NEVER creates or updates the ledger.
 */
export function assessKileaaaReplay(validated, ledgerEntry = null) {
  if (validated?.importStatus !== 'validation_only') {
    fail('UNVERIFIED_INPUT', 'Primero hay que validar los resultados');
  }
  if (ledgerEntry === null) return { status: 'new', publicationAuthorized: false };
  object(ledgerEntry, 'Recibo previo');
  if (ledgerEntry.sourceTournamentId !== validated.tournament.id) {
    fail('LEDGER_CONFLICT', 'El recibo corresponde a otro torneo');
  }
  if (ledgerEntry.resultsFingerprint !== validated.tournament.resultsFingerprint ||
      ledgerEntry.packageDigest !== validated.integrity.digest) {
    return { status: 'revision_requires_manual_review', publicationAuthorized: false };
  }
  return { status: 'already_seen', publicationAuthorized: false };
}
