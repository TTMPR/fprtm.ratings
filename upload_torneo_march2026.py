#!/usr/bin/env python3
"""
Script para cargar los resultados del torneo Albergue Olímpico 2026 (Marzo)
a la base de datos FPRTM (Supabase).

Lee el CSV con formato: Round,WinnerID,LoserID,Scores
donde los IDs tienen formato fprtm|XXXXX

Uso: python3 upload_torneo_march2026.py
"""

import csv
import requests
import sys

# ─── CONFIG ───────────────────────────────────────────────────────────────────
SUPABASE_URL  = 'https://qrvyfdpwtearfpjruwja.supabase.co'
SUPABASE_KEY  = 'sb_publishable_mM59efPqpcgrR3g3_6F_Ww_h1jg4PyV'
CSV_FILE      = 'albergue_olimpico_march2026.csv'

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
    row = next(r for r in POINT_TABLE if diff <= r['maxDiff'])
    a_is_fav = rA >= rB
    if winner_is_A:
        pts = row['fav'] if a_is_fav else row['underdog']
        return pts, -pts
    else:
        pts = row['underdog'] if a_is_fav else row['fav']
        return -pts, pts

# ─── HELPERS SUPABASE ─────────────────────────────────────────────────────────
def sb_get(table, params=''):
    url = f'{SUPABASE_URL}/rest/v1/{table}{params}'
    r = requests.get(url, headers=HEADERS)
    r.raise_for_status()
    return r.json()

def sb_post(table, body):
    url = f'{SUPABASE_URL}/rest/v1/{table}'
    r = requests.post(url, headers=HEADERS, json=body)
    r.raise_for_status()
    return r.json()

def sb_patch(table, query, body):
    url = f'{SUPABASE_URL}/rest/v1/{table}?{query}'
    r = requests.patch(url, headers=HEADERS, json=body)
    r.raise_for_status()
    return r.json()

# ─── PASO 1: Cargar jugadores actuales ────────────────────────────────────────
def load_all_players():
    print('📥 Cargando jugadores de la base de datos...')
    data = sb_get('jugadores',
                  '?select=id,nombre,apellido,rating,nuevo_rating&limit=2000')
    players = {}
    for p in data:
        mid = p['id']
        nombre = f"{p.get('nombre') or ''} {p.get('apellido') or ''}".strip()
        rating = p.get('nuevo_rating') or p.get('rating') or 1500
        players[mid] = {'id': mid, 'name': nombre, 'rating': rating}
    print(f'   → {len(players)} jugadores cargados.')

    # Fallback: intentar tabla "Base de Datos"
    if not players:
        print('   ⚠ Intentando tabla "Base de Datos"...')
        data = sb_get('Base%20de%20Datos',
                      '?select=%22Member%20ID%22,%22First%20Name%22,%22Last%20Name%22,%22Rating%22'
                      '&order=%22Member%20ID%22.asc&limit=2000')
        for p in data:
            mid = p['Member ID']
            nombre = f"{p.get('First Name') or ''} {p.get('Last Name') or ''}".strip()
            players[mid] = {'id': mid, 'name': nombre, 'rating': p.get('Rating') or 1500}
        print(f'   → {len(players)} jugadores cargados (fallback).')

    return players

# ─── PASO 2: Leer y filtrar CSV ───────────────────────────────────────────────
def parse_fprtm_id(raw_id):
    """Extrae el entero de 'fprtm|12345'. Retorna None si no es válido."""
    raw_id = raw_id.strip()
    if not raw_id or ',' in raw_id:
        return None  # vacío o equipo dobles
    if raw_id.startswith('fprtm|'):
        try:
            return int(raw_id.split('|')[1])
        except ValueError:
            return None
    return None

def is_walkover(scores_str):
    """Devuelve True si todos los scores son 0 (walkover)."""
    if not scores_str:
        return False
    parts = [s.strip().lstrip('-') for s in scores_str.split(',') if s.strip()]
    return parts and all(p == '0' for p in parts)

def load_csv():
    print(f'\n📄 Leyendo {CSV_FILE}...')
    matches = []
    skipped_doubles = 0
    skipped_empty   = 0
    skipped_walkover = 0

    with open(CSV_FILE, newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for i, row in enumerate(reader):
            if i == 0:
                continue  # skip header
            if len(row) < 3:
                continue

            rnd       = row[0].strip()
            winner_raw = row[1].strip()
            loser_raw  = row[2].strip()
            scores     = row[3].strip() if len(row) > 3 else ''

            # Skip doubles entries (multiple IDs in one field)
            if ',' in winner_raw or ',' in loser_raw:
                skipped_doubles += 1
                continue

            winner_id = parse_fprtm_id(winner_raw)
            loser_id  = parse_fprtm_id(loser_raw)

            # Skip if either ID is missing/invalid
            if winner_id is None or loser_id is None:
                skipped_empty += 1
                continue

            # Skip walkover matches
            if is_walkover(scores):
                skipped_walkover += 1
                continue

            matches.append({
                'round':     rnd,
                'winner_id': winner_id,
                'loser_id':  loser_id,
                'scores':    scores,
            })

    print(f'   → {len(matches)} partidos válidos (singles).')
    print(f'   → {skipped_doubles} dobles omitidos, {skipped_empty} sin oponente, '
          f'{skipped_walkover} walkovers omitidos.')
    return matches

# ─── PASO 3: Crear torneo ─────────────────────────────────────────────────────
def create_torneo():
    print(f'\n🏆 Creando torneo "{TORNEO_NOMBRE}"...')

    # Check if torneo already exists
    existing = sb_get('torneos', f'?nombre=eq.{requests.utils.quote(TORNEO_NOMBRE)}&select=id,nombre')
    if existing:
        torneo_id = existing[0]['id']
        print(f'   ⚠ Torneo ya existe con ID: {torneo_id}')
        resp = input('   ¿Continuar y agregar partidos a este torneo? [s/N]: ').strip().lower()
        if resp != 's':
            print('   Abortando.')
            return None
        return torneo_id

    try:
        result = sb_post('torneos', {'nombre': TORNEO_NOMBRE, 'fecha': TORNEO_FECHA})
        torneo_id = result[0]['id'] if isinstance(result, list) else result['id']
        print(f'   ✅ Torneo creado con ID: {torneo_id}')
        return torneo_id
    except Exception as e:
        print(f'   ❌ Error creando torneo: {e}')
        return None

# ─── PASO 4: Procesar partidos ────────────────────────────────────────────────
def process_matches(matches, players):
    print(f'\n⚡ Procesando {len(matches)} partidos...')

    # Ratings estáticos (base fija para todo el torneo)
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

        # winner_is_A=True: A=winner, B=loser
        aGain, bGain = get_points(rW, rL, winner_is_A=True)

        pending.append({
            'winner_id':   wid,
            'loser_id':    lid,
            'winner_name': players[wid]['name'],
            'loser_name':  players[lid]['name'],
            'rW':          rW,
            'rL':          rL,
            'wGain':       aGain,
            'lGain':       bGain,
            'round':       m['round'],
            'scores':      m['scores'],
        })

        deltas[wid] += aGain
        deltas[lid] += bGain

    final_ratings = {mid: ratings[mid] + deltas[mid] for mid in ratings}

    print(f'   → {len(pending)} partidos válidos, {skipped} omitidos (ID desconocido).')
    if unknown:
        print(f'   ⚠ IDs no encontrados: {", ".join(sorted(unknown)[:20])}')

    return pending, final_ratings

# ─── PASO 5: Guardar en Supabase ──────────────────────────────────────────────
def save_to_db(pending, players, final_ratings, torneo_id):
    print(f'\n💾 Guardando datos en Supabase...')

    # 5a. Guardar partidos
    print(f'   Guardando {len(pending)} partidos...')
    errors = []
    saved  = 0
    for r in pending:
        try:
            sb_post('partidos', {
                'torneo_id':        torneo_id,
                'jugador_a_id':     r['winner_id'],
                'jugador_b_id':     r['loser_id'],
                'ganador':          'A',
                'rating_a_antes':   r['rW'],
                'rating_b_antes':   r['rL'],
                'rating_a_despues': r['rW'] + r['wGain'],
                'rating_b_despues': r['rL'] + r['lGain'],
                'fecha':            TORNEO_FECHA,
                'nombre_a':         r['winner_name'],
                'nombre_b':         r['loser_name'],
            })
            saved += 1
        except Exception as e:
            errors.append(f'{r["winner_name"]} vs {r["loser_name"]}: {e}')

    print(f'   ✅ {saved} partidos guardados.')
    if errors:
        print(f'   ⚠ {len(errors)} errores:')
        for e in errors[:5]:
            print(f'      {e}')

    # 5b. Actualizar nuevo_rating en jugadores (o Rating en Base de Datos)
    participant_ids = set(r['winner_id'] for r in pending) | set(r['loser_id'] for r in pending)
    print(f'\n   Actualizando ratings de {len(participant_ids)} jugadores...')

    updated = 0
    rating_errors = []
    for mid in participant_ids:
        new_rating = final_ratings[mid]
        old_rating = players[mid]['rating']
        if new_rating == old_rating:
            continue
        try:
            # Try jugadores table first (nuevo_rating column)
            try:
                sb_patch('jugadores', f'id=eq.{mid}', {'nuevo_rating': new_rating})
                updated += 1
            except Exception:
                # Fallback: Base de Datos table
                sb_patch('Base%20de%20Datos',
                         f'%22Member%20ID%22=eq.{mid}',
                         {'Rating': new_rating})
                updated += 1
        except Exception as e:
            rating_errors.append(f'#{mid}: {e}')

    print(f'   ✅ {updated} ratings actualizados.')
    if rating_errors:
        for e in rating_errors[:5]:
            print(f'      ⚠ {e}')

    # 5c. Snapshot por jugador (resultados_evento)
    print(f'\n   Guardando snapshot de participantes...')
    snapshot = {}
    for r in pending:
        for mid, name, rOrig, gain in [
            (r['winner_id'], r['winner_name'], r['rW'], r['wGain']),
            (r['loser_id'],  r['loser_name'],  r['rL'], r['lGain']),
        ]:
            if mid not in snapshot:
                snapshot[mid] = {
                    'id_jugador':    mid,
                    'nombre':        name,
                    'rating_inicio': rOrig,
                    'rating_fin':    rOrig + gain,
                    'ganados':       0,
                    'perdidos':      0,
                    'id_torneo':     torneo_id,
                }
            else:
                snapshot[mid]['rating_fin'] += gain

        snapshot[r['winner_id']]['ganados'] += 1
        snapshot[r['loser_id']]['perdidos'] += 1

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
    print(f'  FPRTM — Carga de Torneo: {TORNEO_NOMBRE}')
    print('=' * 60)

    players = load_all_players()
    if not players:
        print('❌ No se pudieron cargar jugadores. Abortando.')
        sys.exit(1)

    matches = load_csv()
    if not matches:
        print('❌ No se encontraron partidos válidos en el CSV. Abortando.')
        sys.exit(1)

    torneo_id = create_torneo()
    if not torneo_id:
        sys.exit(1)

    pending, final_ratings = process_matches(matches, players)
    if not pending:
        print('❌ No hay partidos con jugadores reconocidos. Abortando.')
        sys.exit(1)

    save_to_db(pending, players, final_ratings, torneo_id)

    participants = set(r['winner_id'] for r in pending) | set(r['loser_id'] for r in pending)
    wins_delta  = sum(1 for r in pending if final_ratings[r['winner_id']] > players[r['winner_id']]['rating'])

    print('\n' + '=' * 60)
    print('  ✅ CARGA COMPLETADA')
    print('=' * 60)
    print(f'  Torneo:         {TORNEO_NOMBRE}')
    print(f'  Fecha:          {TORNEO_FECHA}')
    print(f'  Torneo ID:      {torneo_id}')
    print(f'  Partidos:       {len(pending)}')
    print(f'  Participantes:  {len(participants)}')

    # Show top gainers
    changes = [(mid, final_ratings[mid] - players[mid]['rating']) for mid in participants]
    changes.sort(key=lambda x: -x[1])
    print('\n  Top 5 mayores ganancias:')
    for mid, delta in changes[:5]:
        print(f'    #{mid} {players[mid]["name"]}: +{delta}')
    print('\n  Top 5 mayores pérdidas:')
    for mid, delta in sorted(changes, key=lambda x: x[1])[:5]:
        print(f'    #{mid} {players[mid]["name"]}: {delta}')

if __name__ == '__main__':
    main()
