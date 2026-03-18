#!/usr/bin/env python3
"""
Script para cargar el torneo Albergue Olímpico Open 2026 a Supabase.

Lee el CSV: 'TODOS -Albuergue.Olimpico.2026.csv'
Filtra por eventName = 'Abierto - OPEN'
Los IDs de jugadores vienen en columnas winnerMembershipIds / loserMembershipIds
con formato: fprtm|XXXXX

Uso: python3 upload_open_2026.py
"""

import csv
import requests
import sys

# ─── CONFIG ───────────────────────────────────────────────────────────────────
SUPABASE_URL  = 'https://qrvyfdpwtearfpjruwja.supabase.co'
SUPABASE_KEY  = 'sb_publishable_mM59efPqpcgrR3g3_6F_Ww_h1jg4PyV'
CSV_FILE      = 'TODOS -Albuergue.Olimpico.2026.csv'
EVENT_FILTER  = 'Abierto - OPEN'   # None = cargar todos los eventos

TORNEO_NOMBRE = 'Albergue Olímpico Open 2026'
TORNEO_FECHA  = '2026-03-01'

HEADERS = {
    'apikey':        SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type':  'application/json',
    'Prefer':        'return=representation',
}

# ─── TABLA DE PUNTOS ──────────────────────────────────────────────────────────
POINT_TABLE = [
    {'maxDiff': 24,           'fav': 8,  'underdog': 8  },
    {'maxDiff': 49,           'fav': 7,  'underdog': 10 },
    {'maxDiff': 99,           'fav': 5,  'underdog': 12 },
    {'maxDiff': 149,          'fav': 3,  'underdog': 15 },
    {'maxDiff': 199,          'fav': 2,  'underdog': 20 },
    {'maxDiff': 249,          'fav': 1,  'underdog': 26 },
    {'maxDiff': float('inf'), 'fav': 0,  'underdog': 32 },
]

def get_points(rA, rB, winner_is_A):
    diff = abs(rA - rB)
    row  = next(r for r in POINT_TABLE if diff <= r['maxDiff'])
    a_is_fav = rA >= rB
    if winner_is_A:
        pts = row['fav'] if a_is_fav else row['underdog']
        return pts, -pts
    else:
        pts = row['underdog'] if a_is_fav else row['fav']
        return -pts, pts

# ─── HELPERS SUPABASE ─────────────────────────────────────────────────────────
def sb_get(table, params=''):
    r = requests.get(f'{SUPABASE_URL}/rest/v1/{table}{params}', headers=HEADERS)
    r.raise_for_status()
    return r.json()

def sb_post(table, body):
    r = requests.post(f'{SUPABASE_URL}/rest/v1/{table}', headers=HEADERS, json=body)
    r.raise_for_status()
    return r.json()

def sb_patch(table, query, body):
    r = requests.patch(f'{SUPABASE_URL}/rest/v1/{table}?{query}', headers=HEADERS, json=body)
    r.raise_for_status()
    return r.json()

# ─── PASO 1: Cargar jugadores ─────────────────────────────────────────────────
def load_all_players():
    print('Cargando jugadores de la base de datos...')
    data = sb_get('Base%20de%20Datos',
                  '?select=%22Member%20ID%22,%22First%20Name%22,%22Last%20Name%22,%22Rating%22,%22New%20Rating%22'
                  '&order=%22Member%20ID%22.asc&limit=1000')
    players = {}
    for p in data:
        mid = p['Member ID']
        players[mid] = {
            'id':     mid,
            'name':   f"{p['First Name'] or ''} {p['Last Name'] or ''}".strip(),
            'rating': p['New Rating'] or p['Rating'] or 1500,
        }
    print(f'   -> {len(players)} jugadores cargados.')
    return players

# ─── PASO 2: Parsear ID fprtm ─────────────────────────────────────────────────
def parse_fprtm_id(raw):
    """Extrae int de 'fprtm|12345'. Maneja múltiples IDs separados por coma."""
    raw = raw.strip()
    if not raw:
        return None
    for part in raw.split(','):
        part = part.strip()
        if part.startswith('fprtm|'):
            try:
                return int(part.split('|')[1])
            except ValueError:
                pass
    return None

def is_walkover(scores_str):
    """True si todos los scores son 0."""
    if not scores_str:
        return False
    parts = [s.strip().lstrip('-') for s in scores_str.split(',') if s.strip()]
    return bool(parts) and all(p == '0' for p in parts)

# ─── PASO 3: Leer CSV ─────────────────────────────────────────────────────────
def load_csv():
    label = f'evento "{EVENT_FILTER}"' if EVENT_FILTER else 'todos los eventos'
    print(f'\nLeyendo {CSV_FILE} ({label})...')
    matches          = []
    skipped_event    = 0
    skipped_empty    = 0
    skipped_walkover = 0

    with open(CSV_FILE, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            event_name = row.get('eventName', '').strip()
            if EVENT_FILTER and event_name != EVENT_FILTER:
                skipped_event += 1
                continue

            winner_raw = row.get('winnerMembershipIds', '').strip()
            loser_raw  = row.get('loserMembershipIds',  '').strip()
            scores     = row.get('scores', '').strip()

            winner_id = parse_fprtm_id(winner_raw)
            loser_id  = parse_fprtm_id(loser_raw)

            if winner_id is None or loser_id is None:
                skipped_empty += 1
                continue

            if is_walkover(scores):
                skipped_walkover += 1
                continue

            matches.append({
                'winner_id':  winner_id,
                'loser_id':   loser_id,
                'scores':     scores,
                'event_name': event_name,
                'draw_name':  row.get('drawName', '').strip(),
            })

    print(f'   -> {len(matches)} partidos validos.')
    if skipped_event:
        print(f'   -> {skipped_event} partidos de otros eventos omitidos.')
    if skipped_empty:
        print(f'   -> {skipped_empty} sin ID fprtm valido omitidos.')
    if skipped_walkover:
        print(f'   -> {skipped_walkover} walkovers omitidos.')
    return matches

# ─── PASO 4: Crear torneo ─────────────────────────────────────────────────────
def create_torneo():
    print(f'\nCreando torneo "{TORNEO_NOMBRE}"...')
    existing = sb_get('torneos',
                      f'?nombre=eq.{requests.utils.quote(TORNEO_NOMBRE)}&select=id,nombre')
    if existing:
        torneo_id = existing[0]['id']
        print(f'   AVISO: El torneo ya existe (ID: {torneo_id}).')
        resp = input('   Continuar y agregar partidos a este torneo? [s/N]: ').strip().lower()
        if resp != 's':
            print('   Abortando.')
            return None
        return torneo_id

    result    = sb_post('torneos', {'nombre': TORNEO_NOMBRE, 'fecha': TORNEO_FECHA})
    torneo_id = result[0]['id'] if isinstance(result, list) else result['id']
    print(f'   Torneo creado con ID: {torneo_id}')
    return torneo_id

# ─── PASO 5: Procesar partidos ────────────────────────────────────────────────
def process_matches(matches, players):
    print(f'\nProcesando {len(matches)} partidos...')

    ratings = {mid: p['rating'] for mid, p in players.items()}
    deltas  = {mid: 0          for mid in players}

    pending = []
    unknown = set()
    skipped = 0

    for m in matches:
        wid = m['winner_id']
        lid = m['loser_id']

        if wid not in players:
            unknown.add(str(wid))
            skipped += 1
            continue
        if lid not in players:
            unknown.add(str(lid))
            skipped += 1
            continue

        rW = ratings[wid]
        rL = ratings[lid]
        wGain, lGain = get_points(rW, rL, winner_is_A=True)

        pending.append({
            'idA':   wid,   # ganador
            'idB':   lid,   # perdedor
            'nameA': players[wid]['name'],
            'nameB': players[lid]['name'],
            'rA':    rW,
            'rB':    rL,
            'aGain': wGain,
            'bGain': lGain,
        })

        deltas[wid] += wGain
        deltas[lid] += lGain

    final_ratings = {mid: ratings[mid] + deltas[mid] for mid in ratings}

    print(f'   -> {len(pending)} partidos listos, {skipped} omitidos (ID no en BD).')
    if unknown:
        print(f'   AVISO IDs no encontrados: {", ".join(sorted(unknown))}')

    return pending, final_ratings

# ─── PASO 6: Guardar en Supabase ──────────────────────────────────────────────
def save_to_db(pending, players, final_ratings, torneo_id):
    print(f'\nGuardando en Supabase...')

    # 6a. Partidos
    print(f'   Guardando {len(pending)} partidos...')
    errors = []
    saved  = 0
    for r in pending:
        try:
            sb_post('partidos', {
                'torneo_id':        torneo_id,
                'jugador_a_id':     r['idA'],
                'jugador_b_id':     r['idB'],
                'ganador':          'A',
                'rating_a_antes':   r['rA'],
                'rating_b_antes':   r['rB'],
                'rating_a_despues': r['rA'] + r['aGain'],
                'rating_b_despues': r['rB'] + r['bGain'],
                'fecha':            TORNEO_FECHA,
                'nombre_a':         r['nameA'],
                'nombre_b':         r['nameB'],
            })
            saved += 1
        except Exception as e:
            errors.append(f'{r["nameA"]} vs {r["nameB"]}: {e}')

    print(f'   {saved} partidos guardados.')
    if errors:
        print(f'   {len(errors)} errores:')
        for e in errors[:5]:
            print(f'      {e}')

    # 6b. Ratings
    participant_ids = {r['idA'] for r in pending} | {r['idB'] for r in pending}
    print(f'\n   Actualizando ratings de {len(participant_ids)} jugadores...')
    updated = 0
    for mid in participant_ids:
        new_r = final_ratings[mid]
        if new_r == players[mid]['rating']:
            continue
        try:
            sb_patch('Base%20de%20Datos',
                     f'%22Member%20ID%22=eq.{mid}',
                     {'New Rating': new_r})
            updated += 1
        except Exception as e:
            print(f'      AVISO #{mid}: {e}')

    print(f'   {updated} ratings actualizados.')

    # 6c. Snapshot resultados_evento
    print(f'\n   Guardando snapshot de participantes...')
    snapshot = {}
    for r in pending:
        for mid, name, rOrig, gain in [
            (r['idA'], r['nameA'], r['rA'], r['aGain']),
            (r['idB'], r['nameB'], r['rB'], r['bGain']),
        ]:
            if mid not in snapshot:
                snapshot[mid] = {
                    'id_jugador':    mid,
                    'nombre':        name,
                    'club':          players[mid].get('club', ''),
                    'rating_inicio': rOrig,
                    'rating_fin':    rOrig + gain,
                    'ganados':       0,
                    'perdidos':      0,
                    'id_torneo':     torneo_id,
                }
            else:
                snapshot[mid]['rating_fin'] += gain

        snapshot[r['idA']]['ganados']  += 1
        snapshot[r['idB']]['perdidos'] += 1

    rows = list(snapshot.values())
    try:
        for i in range(0, len(rows), 50):
            sb_post('resultados_evento', rows[i:i+50])
        print(f'   {len(rows)} snapshots guardados.')
    except Exception as e:
        print(f'   AVISO resultados_evento: {e}')

# ─── MAIN ─────────────────────────────────────────────────────────────────────
def main():
    print('=' * 60)
    print(f'  FPTM -- Carga: {TORNEO_NOMBRE}')
    print('=' * 60)

    players = load_all_players()
    if not players:
        print('ERROR: No se pudieron cargar jugadores.')
        sys.exit(1)

    matches = load_csv()
    if not matches:
        print('ERROR: No se encontraron partidos validos.')
        sys.exit(1)

    torneo_id = create_torneo()
    if not torneo_id:
        sys.exit(1)

    pending, final_ratings = process_matches(matches, players)
    if not pending:
        print('ERROR: No hay partidos con jugadores reconocidos.')
        sys.exit(1)

    save_to_db(pending, players, final_ratings, torneo_id)

    participants = {r['idA'] for r in pending} | {r['idB'] for r in pending}
    changes = sorted(
        [(mid, final_ratings[mid] - players[mid]['rating']) for mid in participants],
        key=lambda x: -x[1]
    )

    print('\n' + '=' * 60)
    print('  CARGA COMPLETADA')
    print('=' * 60)
    print(f'  Torneo:        {TORNEO_NOMBRE}')
    print(f'  Torneo ID:     {torneo_id}')
    print(f'  Evento:        {EVENT_FILTER or "TODOS"}')
    print(f'  Partidos:      {len(pending)}')
    print(f'  Participantes: {len(participants)}')

    print('\n  Top 5 ganancias:')
    for mid, delta in changes[:5]:
        print(f'    #{mid} {players[mid]["name"]}: +{delta}  '
              f'({players[mid]["rating"]} -> {final_ratings[mid]})')
    print('\n  Top 5 perdidas:')
    for mid, delta in changes[-5:][::-1]:
        print(f'    #{mid} {players[mid]["name"]}: {delta}  '
              f'({players[mid]["rating"]} -> {final_ratings[mid]})')

if __name__ == '__main__':
    main()
