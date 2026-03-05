#!/usr/bin/env python3
"""
Script para cargar los resultados del torneo Albergue Olímpico 2026
a la base de datos FPRTM (Supabase).

Uso: python3 upload_torneo.py
"""

import csv
import json
import requests
import sys

# ─── CONFIG ───────────────────────────────────────────────────────────────────
SUPABASE_URL = 'https://qrvyfdpwtearfpjruwja.supabase.co'
SUPABASE_KEY = 'sb_publishable_mM59efPqpcgrR3g3_6F_Ww_h1jg4PyV'
CSV_FILE     = 'albergue_olimpico_2026.csv'

TORNEO_NOMBRE = 'Albergue Olímpico 2026'
TORNEO_FECHA  = '2026-03-01'

HEADERS = {
    'apikey':        SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type':  'application/json',
    'Prefer':        'return=representation',
}

# ─── TABLA DE PUNTOS (igual que en index.html) ────────────────────────────────
POINT_TABLE = [
    {'maxDiff': 24,       'fav': 8,  'underdog': 8  },
    {'maxDiff': 49,       'fav': 7,  'underdog': 10 },
    {'maxDiff': 99,       'fav': 5,  'underdog': 12 },
    {'maxDiff': 149,      'fav': 3,  'underdog': 15 },
    {'maxDiff': 199,      'fav': 2,  'underdog': 20 },
    {'maxDiff': 249,      'fav': 1,  'underdog': 26 },
    {'maxDiff': float('inf'), 'fav': 0, 'underdog': 32 },
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

# ─── JUGADORES FALTANTES ──────────────────────────────────────────────────────
# Estos 6 jugadores aparecen en el CSV pero no están en la base de datos FPRTM
MISSING_PLAYERS = [
    {'Member ID': 27578, 'First Name': 'Elio',   'Last Name': 'Nunez Mercado',      'Rating': 1500},
    {'Member ID': 33583, 'First Name': 'Diego',  'Last Name': 'Alamo Parra',        'Rating': 1500},
    {'Member ID': 39007, 'First Name': 'Luis',   'Last Name': 'Rivera Soto',        'Rating': 1500},
    {'Member ID': 42772, 'First Name': 'Eliel',  'Last Name': 'Cruz Rivera',        'Rating': 1500},
    {'Member ID': 63279, 'First Name': 'Amir',   'Last Name': 'Berrios Padilla',    'Rating': 1500},
    {'Member ID': 90854, 'First Name': 'Yadier', 'Last Name': 'Velazquez Vazquez',  'Rating': 1500},
]

# ─── PASO 1: Cargar jugadores actuales ────────────────────────────────────────
def load_all_players():
    print('📥 Cargando jugadores de la base de datos...')
    data = sb_get('Base%20de%20Datos',
                  '?select=%22Member%20ID%22,%22First%20Name%22,%22Last%20Name%22,%22Rating%22'
                  '&order=%22Member%20ID%22.asc&limit=1000')
    players = {}
    for p in data:
        mid = p['Member ID']
        players[mid] = {
            'id':     mid,
            'name':   f"{p['First Name'] or ''} {p['Last Name'] or ''}".strip(),
            'rating': p['Rating'] or 1500,
        }
    print(f'   → {len(players)} jugadores cargados.')
    return players

# ─── PASO 2: Agregar jugadores faltantes ─────────────────────────────────────
def add_missing_players(players):
    print('\n➕ Verificando jugadores faltantes...')
    added = 0
    for mp in MISSING_PLAYERS:
        mid = mp['Member ID']
        if mid in players:
            print(f'   ✓ #{mid} {mp["First Name"]} {mp["Last Name"]} ya existe (rating: {players[mid]["rating"]})')
        else:
            print(f'   + Agregando #{mid} {mp["First Name"]} {mp["Last Name"]}...')
            try:
                sb_post('Base%20de%20Datos', mp)
                players[mid] = {
                    'id':     mid,
                    'name':   f'{mp["First Name"]} {mp["Last Name"]}',
                    'rating': mp['Rating'],
                }
                print(f'     ✅ Agregado exitosamente.')
                added += 1
            except Exception as e:
                print(f'     ❌ Error: {e}')
    print(f'   → {added} jugadores nuevos agregados.')
    return players

# ─── PASO 3: Leer CSV ─────────────────────────────────────────────────────────
def load_csv():
    print(f'\n📄 Leyendo {CSV_FILE}...')
    matches = []
    with open(CSV_FILE, newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for i, row in enumerate(reader):
            if i == 0 and any(h.lower() in ['jugador a','jugador b','ganador'] for h in row):
                continue  # skip header
            if len(row) < 3:
                continue
            pA = row[0].strip()
            pB = row[1].strip()
            win = row[2].strip().upper()
            if pA and pB:
                matches.append({'pA': pA, 'pB': pB, 'win': win})
    print(f'   → {len(matches)} partidos leídos.')
    return matches

# ─── PASO 4: Crear torneo ─────────────────────────────────────────────────────
def create_torneo():
    print(f'\n🏆 Creando torneo "{TORNEO_NOMBRE}"...')
    try:
        result = sb_post('torneos', {'nombre': TORNEO_NOMBRE, 'fecha': TORNEO_FECHA})
        torneo_id = result[0]['id'] if isinstance(result, list) else result['id']
        print(f'   ✅ Torneo creado con ID: {torneo_id}')
        return torneo_id
    except Exception as e:
        print(f'   ❌ Error creando torneo: {e}')
        return None

# ─── PASO 5: Procesar partidos ────────────────────────────────────────────────
def process_matches(matches, players, torneo_id):
    print(f'\n⚡ Procesando {len(matches)} partidos...')

    # initial ratings — fixed for the entire tournament (static base)
    ratings = {mid: p['rating'] for mid, p in players.items()}
    deltas   = {mid: 0          for mid in players}

    def find_player(q):
        if q.startswith('#'):
            mid = int(q[1:])
            return mid if mid in players else None
        # by name fallback
        q_low = q.lower()
        for mid, p in players.items():
            if p['name'].lower() == q_low:
                return mid
        return None

    pending = []
    unknown = set()
    skipped = 0

    for row in matches:
        id_a = find_player(row['pA'])
        id_b = find_player(row['pB'])
        if id_a is None:
            unknown.add(row['pA'])
            skipped += 1
            continue
        if id_b is None:
            unknown.add(row['pB'])
            skipped += 1
            continue

        rA = ratings[id_a]
        rB = ratings[id_b]
        winner_is_A = row['win'] == 'A'
        aGain, bGain = get_points(rA, rB, winner_is_A)

        pending.append({
            'idA': id_a, 'idB': id_b,
            'nameA': players[id_a]['name'], 'nameB': players[id_b]['name'],
            'rA': rA, 'rB': rB,
            'aGain': aGain, 'bGain': bGain,
            'winner': 'A' if winner_is_A else 'B',
        })

        # accumulate deltas — DO NOT update ratings mid-tournament
        deltas[id_a] += aGain
        deltas[id_b] += bGain

    # apply all deltas at the end (single update per player)
    final_ratings = {mid: ratings[mid] + deltas[mid] for mid in ratings}

    print(f'   → {len(pending)} partidos válidos, {skipped} omitidos.')
    if unknown:
        print(f'   ⚠ IDs no encontrados: {", ".join(sorted(unknown))}')

    return pending, final_ratings

# ─── PASO 6: Guardar en Supabase ──────────────────────────────────────────────
def save_to_db(pending, players, ratings, torneo_id):
    print(f'\n💾 Guardando datos en Supabase...')

    # 6a. Guardar partidos
    print(f'   Guardando {len(pending)} partidos...')
    errors = []
    saved_matches = 0
    for r in pending:
        try:
            sb_post('partidos', {
                'torneo_id':        torneo_id,
                'jugador_a_id':     r['idA'],
                'jugador_b_id':     r['idB'],
                'ganador':          r['winner'],
                'rating_a_antes':   r['rA'],
                'rating_b_antes':   r['rB'],
                'rating_a_despues': r['rA'] + r['aGain'],
                'rating_b_despues': r['rB'] + r['bGain'],
                'fecha':            TORNEO_FECHA,
                'nombre_a':         r['nameA'],
                'nombre_b':         r['nameB'],
            })
            saved_matches += 1
        except Exception as e:
            errors.append(f'  partido {r["nameA"]} vs {r["nameB"]}: {e}')

    print(f'   ✅ {saved_matches} partidos guardados.')
    if errors:
        print(f'   ⚠ {len(errors)} errores en partidos:')
        for e in errors[:5]:
            print(f'      {e}')

    # 6b. Actualizar ratings
    print(f'\n   Actualizando ratings...')
    # find which players participated
    participant_ids = set()
    for r in pending:
        participant_ids.add(r['idA'])
        participant_ids.add(r['idB'])

    updated = 0
    rating_errors = []
    for mid in participant_ids:
        new_rating = ratings[mid]
        old_rating = players[mid]['rating']
        if new_rating != old_rating:
            try:
                sb_patch('Base%20de%20Datos',
                         f'%22Member%20ID%22=eq.{mid}',
                         {'Rating': new_rating})
                updated += 1
            except Exception as e:
                rating_errors.append(f'  #{mid} {players[mid]["name"]}: {e}')

    print(f'   ✅ {updated} ratings actualizados.')
    if rating_errors:
        for e in rating_errors[:5]:
            print(f'      {e}')

    # 6c. Guardar resultados_evento (snapshot por jugador)
    if torneo_id:
        print(f'\n   Guardando snapshot de participantes...')
        # Build snapshot: rating_inicio = original, rating_fin = final
        snapshot_map = {}
        for r in pending:
            for mid, name, rOrig, gain in [
                (r['idA'], r['nameA'], r['rA'], r['aGain']),
                (r['idB'], r['nameB'], r['rB'], r['bGain']),
            ]:
                if mid not in snapshot_map:
                    snapshot_map[mid] = {
                        'id_jugador':     mid,
                        'nombre':         name,
                        'club':           players[mid].get('club', ''),
                        'rating_inicio':  rOrig,
                        'rating_fin':     rOrig + gain,
                        'ganados':        0,
                        'perdidos':       0,
                        'id_torneo':      torneo_id,
                    }
                else:
                    snapshot_map[mid]['rating_fin'] += gain

            # tally wins/losses
            winner_id = r['idA'] if r['winner'] == 'A' else r['idB']
            loser_id  = r['idB'] if r['winner'] == 'A' else r['idA']
            snapshot_map[winner_id]['ganados'] += 1
            snapshot_map[loser_id]['perdidos'] += 1

        rows = list(snapshot_map.values())
        try:
            for i in range(0, len(rows), 50):
                sb_post('resultados_evento', rows[i:i+50])
            print(f'   ✅ {len(rows)} snapshots de participantes guardados.')
        except Exception as e:
            print(f'   ⚠ Error guardando resultados_evento: {e}')

# ─── MAIN ─────────────────────────────────────────────────────────────────────
def main():
    print('=' * 60)
    print(f'  FPRTM — Carga de Torneo: {TORNEO_NOMBRE}')
    print('=' * 60)

    players = load_all_players()
    players = add_missing_players(players)
    matches  = load_csv()

    if not matches:
        print('❌ No se encontraron partidos en el CSV. Abortando.')
        sys.exit(1)

    torneo_id = create_torneo()
    if not torneo_id:
        print('❌ No se pudo crear el torneo. Abortando.')
        sys.exit(1)

    pending, final_ratings = process_matches(matches, players, torneo_id)

    if not pending:
        print('❌ No hay partidos válidos para procesar. Abortando.')
        sys.exit(1)

    save_to_db(pending, players, final_ratings, torneo_id)

    print('\n' + '=' * 60)
    print('  ✅ CARGA COMPLETADA')
    print('=' * 60)
    print(f'  Torneo ID:        {torneo_id}')
    print(f'  Partidos cargados: {len(pending)}')
    print(f'  Participantes:    {len(set(r["idA"] for r in pending) | set(r["idB"] for r in pending))}')

if __name__ == '__main__':
    main()
