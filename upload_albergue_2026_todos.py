#!/usr/bin/env python3
"""
Script para cargar TODOS los partidos del torneo Albergue Olímpico 2026
a la base de datos FPTM (Supabase).

Lee el CSV con formato: Round,WinnerID,LoserID,Scores
donde los IDs tienen formato fprtm|XXXXX

Uso: python3 upload_albergue_2026_todos.py
"""

import csv
import requests
import sys

# ─── CONFIG ───────────────────────────────────────────────────────────────────
SUPABASE_URL  = 'https://qrvyfdpwtearfpjruwja.supabase.co'
SUPABASE_KEY  = 'sb_publishable_mM59efPqpcgrR3g3_6F_Ww_h1jg4PyV'
CSV_FILE      = 'Albuergue.Olimpico.2026.csv'

TORNEO_NOMBRE = 'Albergue Olímpico 2026'
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

# ─── PASO 1: Cargar jugadores actuales ────────────────────────────────────────
def load_all_players():
    print('📥 Cargando jugadores de la base de datos...')
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
    print(f'   → {len(players)} jugadores cargados.')
    return players

# ─── PASO 2: Leer y filtrar CSV ───────────────────────────────────────────────
def parse_fprtm_id(raw_id):
    """Extrae entero de 'fprtm|12345'.
    Si el campo tiene múltiples IDs (ej. 'fprtm|26683,stadium-tt|38117'),
    usa el ID fprtm| e ignora el resto.
    Retorna None si no hay ningún ID fprtm| válido.
    """
    raw_id = raw_id.strip()
    if not raw_id:
        return None
    parts = [p.strip() for p in raw_id.split(',')]
    fprtm_parts = [p for p in parts if p.startswith('fprtm|')]
    if not fprtm_parts:
        return None
    try:
        return int(fprtm_parts[0].split('|')[1])
    except ValueError:
        return None

def is_walkover(scores_str):
    """True si todos los scores son 0 (walkover)."""
    if not scores_str:
        return False
    parts = [s.strip().lstrip('-') for s in scores_str.split(',') if s.strip()]
    return bool(parts) and all(p == '0' for p in parts)

def load_csv():
    print(f'\n📄 Leyendo {CSV_FILE}...')
    matches          = []
    skipped_empty    = 0
    skipped_walkover = 0

    with open(CSV_FILE, newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for i, row in enumerate(reader):
            if i == 0:
                continue  # header
            if len(row) < 3:
                continue

            rnd        = row[0].strip()
            winner_raw = row[1].strip()
            loser_raw  = row[2].strip()
            scores     = row[3].strip() if len(row) > 3 else ''

            winner_id = parse_fprtm_id(winner_raw)
            loser_id  = parse_fprtm_id(loser_raw)

            if winner_id is None or loser_id is None:
                skipped_empty += 1
                continue

            if is_walkover(scores):
                skipped_walkover += 1
                continue

            matches.append({
                'round':     rnd,
                'winner_id': winner_id,
                'loser_id':  loser_id,
                'scores':    scores,
            })

    print(f'   → {len(matches)} partidos válidos.')
    print(f'   → {skipped_empty} sin oponente (forfeit), '
          f'{skipped_walkover} walkovers omitidos.')
    return matches

# ─── PASO 3: Crear torneo ─────────────────────────────────────────────────────
def create_torneo():
    print(f'\n🏆 Creando torneo "{TORNEO_NOMBRE}"...')

    existing = sb_get('torneos',
                      f'?nombre=eq.{requests.utils.quote(TORNEO_NOMBRE)}&select=id,nombre')
    if existing:
        torneo_id = existing[0]['id']
        print(f'   ⚠ Torneo ya existe (ID: {torneo_id}).')
        resp = input('   ¿Continuar y agregar partidos a este torneo? [s/N]: ').strip().lower()
        if resp != 's':
            print('   Abortando.')
            return None
        return torneo_id

    result    = sb_post('torneos', {'nombre': TORNEO_NOMBRE, 'fecha': TORNEO_FECHA})
    torneo_id = result[0]['id'] if isinstance(result, list) else result['id']
    print(f'   ✅ Torneo creado con ID: {torneo_id}')
    return torneo_id

# ─── PASO 4: Procesar partidos ────────────────────────────────────────────────
def process_matches(matches, players):
    print(f'\n⚡ Procesando {len(matches)} partidos...')

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
            'idA':   wid,
            'idB':   lid,
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

    print(f'   → {len(pending)} partidos válidos, {skipped} omitidos (ID desconocido).')
    if unknown:
        print(f'   ⚠ IDs no encontrados en BD: {", ".join(sorted(unknown))}')

    return pending, final_ratings

# ─── PASO 5: Guardar en Supabase ──────────────────────────────────────────────
def save_to_db(pending, players, final_ratings, torneo_id):
    print(f'\n💾 Guardando datos en Supabase...')

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

    print(f'   ✅ {saved} partidos guardados.')
    if errors:
        print(f'   ⚠ {len(errors)} errores:')
        for e in errors[:5]:
            print(f'      {e}')

    participant_ids = {r['idA'] for r in pending} | {r['idB'] for r in pending}
    print(f'\n   Actualizando ratings de {len(participant_ids)} jugadores...')

    updated = 0
    rating_errors = []
    for mid in participant_ids:
        new_rating = final_ratings[mid]
        if new_rating == players[mid]['rating']:
            continue
        try:
            sb_patch('Base%20de%20Datos',
                     f'%22Member%20ID%22=eq.{mid}',
                     {'New Rating': new_rating})
            updated += 1
        except Exception as e:
            rating_errors.append(f'#{mid}: {e}')

    print(f'   ✅ {updated} ratings actualizados.')
    if rating_errors:
        for e in rating_errors[:5]:
            print(f'      ⚠ {e}')

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

        snapshot[r['idA']]['ganados'] += 1
        snapshot[r['idB']]['perdidos'] += 1

    rows = list(snapshot.values())
    try:
        for i in range(0, len(rows), 50):
            sb_post('resultados_evento', rows[i:i+50])
        print(f'   ✅ {len(rows)} snapshots guardados.')
    except Exception as e:
        print(f'   ⚠ Error guardando resultados_evento: {e}')

# ─── MAIN ─────────────────────────────────────────────────────────────────────
def main():
    print('=' * 60)
    print(f'  FPTM — Carga de Torneo: {TORNEO_NOMBRE}')
    print('=' * 60)

    players = load_all_players()
    if not players:
        print('❌ No se pudieron cargar jugadores. Abortando.')
        sys.exit(1)

    matches = load_csv()
    if not matches:
        print('❌ No se encontraron partidos válidos. Abortando.')
        sys.exit(1)

    torneo_id = create_torneo()
    if not torneo_id:
        sys.exit(1)

    pending, final_ratings = process_matches(matches, players)
    if not pending:
        print('❌ No hay partidos con jugadores reconocidos. Abortando.')
        sys.exit(1)

    save_to_db(pending, players, final_ratings, torneo_id)

    participants = {r['idA'] for r in pending} | {r['idB'] for r in pending}
    changes = sorted(
        [(mid, final_ratings[mid] - players[mid]['rating']) for mid in participants],
        key=lambda x: -x[1]
    )

    print('\n' + '=' * 60)
    print('  ✅ CARGA COMPLETADA')
    print('=' * 60)
    print(f'  Torneo:         {TORNEO_NOMBRE}')
    print(f'  Torneo ID:      {torneo_id}')
    print(f'  Partidos:       {len(pending)}')
    print(f'  Participantes:  {len(participants)}')
    print('\n  Top 5 ganancias:')
    for mid, delta in changes[:5]:
        print(f'    #{mid} {players[mid]["name"]}: +{delta}  '
              f'({players[mid]["rating"]} → {final_ratings[mid]})')
    print('\n  Top 5 pérdidas:')
    for mid, delta in changes[-5:][::-1]:
        print(f'    #{mid} {players[mid]["name"]}: {delta}  '
              f'({players[mid]["rating"]} → {final_ratings[mid]})')

if __name__ == '__main__':
    main()
