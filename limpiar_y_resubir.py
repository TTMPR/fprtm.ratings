#!/usr/bin/env python3
"""
Limpia un torneo de la BD (partidos + resultados_evento + registro torneo)
y lo re-procesa desde el CSV con la logica de rating ESTATICO.

Uso:
  python3 limpiar_y_resubir.py                  # ultimo torneo
  python3 limpiar_y_resubir.py "Nombre torneo"  # torneo especifico
  python3 limpiar_y_resubir.py --list           # solo listar torneos
"""

import sys
import requests

# ─── CONFIG ───────────────────────────────────────────────────────────────────
SUPABASE_URL  = 'https://qrvyfdpwtearfpjruwja.supabase.co'
SUPABASE_KEY  = 'sb_publishable_mM59efPqpcgrR3g3_6F_Ww_h1jg4PyV'
CSV_FILE      = 'albergue_olimpico_2026.csv'
TORNEO_NOMBRE = 'Albergue Olimpico 2026'
TORNEO_FECHA  = '2026-03-01'

HEADERS = {
    'apikey':        SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type':  'application/json',
    'Prefer':        'return=representation',
}

POINT_TABLE = [
    {'maxDiff': 24,           'fav': 8,  'underdog': 8  },
    {'maxDiff': 49,           'fav': 7,  'underdog': 10 },
    {'maxDiff': 99,           'fav': 5,  'underdog': 12 },
    {'maxDiff': 149,          'fav': 3,  'underdog': 15 },
    {'maxDiff': 199,          'fav': 2,  'underdog': 20 },
    {'maxDiff': 249,          'fav': 1,  'underdog': 26 },
    {'maxDiff': float('inf'), 'fav': 0,  'underdog': 32 },
]

# ─── HELPERS ──────────────────────────────────────────────────────────────────
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

def sb_delete(table, query):
    r = requests.delete(f'{SUPABASE_URL}/rest/v1/{table}?{query}', headers=HEADERS)
    r.raise_for_status()
    return r

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

# ─── LISTAR TORNEOS ───────────────────────────────────────────────────────────
def list_torneos():
    torneos = sb_get('torneos', '?select=id,nombre,fecha&order=id.desc&limit=20')
    print('\nTorneos en la base de datos:')
    for t in torneos:
        # contar partidos
        pts = sb_get('partidos', f'?torneo_id=eq.{t["id"]}&select=id')
        print(f'  ID {t["id"]:>3}: {t["nombre"]}  ({t["fecha"]})  [{len(pts)} partidos]')
    return torneos

# ─── LIMPIAR TORNEO ───────────────────────────────────────────────────────────
def limpiar_torneo(torneo_id, torneo_nombre):
    print(f'\nLimpiando torneo ID={torneo_id} "{torneo_nombre}"...')

    # 1. Recuperar ratings ANTES de borrar (los que el sistema guardó como rating_a_antes)
    partidos_antes = sb_get('partidos',
        f'?torneo_id=eq.{torneo_id}'
        '&select=jugador_a_id,jugador_b_id,rating_a_antes,rating_b_antes')

    # Primer rating_X_antes de cada jugador = rating inicial usado
    ratings_iniciales = {}
    for p in partidos_antes:
        if p['jugador_a_id'] and p['jugador_a_id'] not in ratings_iniciales:
            ratings_iniciales[p['jugador_a_id']] = p['rating_a_antes']
        if p['jugador_b_id'] and p['jugador_b_id'] not in ratings_iniciales:
            ratings_iniciales[p['jugador_b_id']] = p['rating_b_antes']

    print(f'  Ratings iniciales recuperados para {len(ratings_iniciales)} jugadores.')

    # 2. Revertir rating en Base de Datos al rating inicial de cada jugador
    print('  Revirtiendo ratings en Base de Datos...')
    reverted = 0
    for mid, rating_inicial in ratings_iniciales.items():
        try:
            sb_patch('Base%20de%20Datos', f'%22Member%20ID%22=eq.{mid}', {'Rating': rating_inicial})
            reverted += 1
        except Exception as e:
            print(f'    ERROR revirtiendo #{mid}: {e}')
    print(f'  {reverted} ratings revertidos al valor inicial.')

    # 3. Borrar partidos del torneo
    print('  Borrando partidos...')
    try:
        sb_delete('partidos', f'torneo_id=eq.{torneo_id}')
        print('  Partidos borrados.')
    except Exception as e:
        print(f'  ERROR borrando partidos: {e}')

    # 4. Borrar resultados_evento del torneo
    print('  Borrando resultados_evento...')
    try:
        sb_delete('resultados_evento', f'id_torneo=eq.{torneo_id}')
        print('  resultados_evento borrados.')
    except Exception as e:
        print(f'  ERROR (puede ser normal si no existia la tabla): {e}')

    # 5. Borrar registro del torneo
    print('  Borrando registro del torneo...')
    try:
        sb_delete('torneos', f'id=eq.{torneo_id}')
        print('  Torneo borrado.')
    except Exception as e:
        print(f'  ERROR borrando torneo: {e}')

    print(f'  Limpieza completada.')
    return ratings_iniciales

# ─── CARGAR CSV ───────────────────────────────────────────────────────────────
import csv as csvmod

def load_csv():
    matches = []
    with open(CSV_FILE, newline='', encoding='utf-8') as f:
        reader = csvmod.reader(f)
        for i, row in enumerate(reader):
            if i == 0 and any(h.lower() in ['jugador a','jugador b','ganador'] for h in row):
                continue
            if len(row) < 3:
                continue
            pA, pB, win = row[0].strip(), row[1].strip(), row[2].strip().upper()
            if pA and pB:
                matches.append({'pA': pA, 'pB': pB, 'win': win})
    return matches

# ─── RE-SUBIR CON LOGICA ESTATICA ─────────────────────────────────────────────
def resubir(matches, ratings_iniciales_revertidos):
    print(f'\nRe-procesando {len(matches)} partidos con logica ESTATICA...')

    # Cargar jugadores frescos de la BD (ya revertidos)
    data = sb_get('Base%20de%20Datos',
        '?select=%22Member%20ID%22,%22First%20Name%22,%22Last%20Name%22,%22Rating%22'
        '&limit=2000')
    players = {}
    for p in data:
        mid = p['Member ID']
        players[mid] = {
            'name':   f"{p['First Name'] or ''} {p['Last Name'] or ''}".strip(),
            'rating': p['Rating'] or 1500,
        }

    def find_player(q):
        if q.startswith('#'):
            mid = int(q[1:])
            return mid if mid in players else None
        q_low = q.lower()
        for mid, p in players.items():
            if p['name'].lower() == q_low:
                return mid
        return None

    # Rating inicial FIJO para todos los partidos
    ratings = {mid: p['rating'] for mid, p in players.items()}
    deltas  = {mid: 0 for mid in players}

    pending = []
    unknown = set()

    for row in matches:
        id_a = find_player(row['pA'])
        id_b = find_player(row['pB'])
        if id_a is None: unknown.add(row['pA']); continue
        if id_b is None: unknown.add(row['pB']); continue

        rA = ratings[id_a]   # siempre el inicial — NO cambia entre partidos
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

        # Acumular delta — NO actualizar ratings entre partidos
        deltas[id_a] += aGain
        deltas[id_b] += bGain

    if unknown:
        print(f'  Jugadores no encontrados: {", ".join(sorted(unknown))}')

    final_ratings = {mid: ratings[mid] + deltas[mid] for mid in ratings}
    print(f'  {len(pending)} partidos procesados correctamente.')

    # Crear torneo
    print(f'  Creando torneo "{TORNEO_NOMBRE}"...')
    result = sb_post('torneos', {'nombre': TORNEO_NOMBRE, 'fecha': TORNEO_FECHA})
    torneo_id = result[0]['id'] if isinstance(result, list) else result['id']
    print(f'  Torneo creado con ID={torneo_id}.')

    # Guardar partidos
    print(f'  Guardando {len(pending)} partidos...')
    saved = 0
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
            saved += 1
        except Exception as e:
            print(f'    ERROR partido {r["nameA"]} vs {r["nameB"]}: {e}')
    print(f'  {saved} partidos guardados.')

    # Actualizar ratings (una sola vez por jugador)
    print('  Actualizando ratings (una vez por jugador)...')
    participant_ids = set(r['idA'] for r in pending) | set(r['idB'] for r in pending)
    updated = 0
    for mid in participant_ids:
        new_r = final_ratings[mid]
        old_r = players[mid]['rating']
        if new_r != old_r:
            try:
                sb_patch('Base%20de%20Datos', f'%22Member%20ID%22=eq.{mid}', {'Rating': new_r})
                delta = new_r - old_r
                print(f'    #{mid} {players[mid]["name"]}: {old_r} -> {new_r}  ({delta:+d})')
                updated += 1
            except Exception as e:
                print(f'    ERROR actualizando #{mid}: {e}')

    # Guardar snapshot resultados_evento
    print(f'  Guardando snapshot de participantes...')
    snapshot_map = {}
    for r in pending:
        for mid, name, rInit, gain in [
            (r['idA'], r['nameA'], r['rA'], r['aGain']),
            (r['idB'], r['nameB'], r['rB'], r['bGain']),
        ]:
            if mid not in snapshot_map:
                p_obj = players.get(mid, {})
                snapshot_map[mid] = {
                    'id_torneo':    torneo_id,
                    'id_jugador':   mid,
                    'nombre':       name,
                    'club':         p_obj.get('club', ''),
                    'rating_inicio': rInit,
                    'rating_fin':   rInit,
                    'ganados': 0, 'perdidos': 0,
                }
            snapshot_map[mid]['rating_fin'] += gain
            winnerIsA = r['winner'] == 'A'
            if mid == r['idA']:
                if winnerIsA: snapshot_map[mid]['ganados'] += 1
                else:         snapshot_map[mid]['perdidos'] += 1
            else:
                if not winnerIsA: snapshot_map[mid]['ganados'] += 1
                else:             snapshot_map[mid]['perdidos'] += 1

    rows = list(snapshot_map.values())
    for i in range(0, len(rows), 50):
        try:
            sb_post('resultados_evento', rows[i:i+50])
        except Exception as e:
            print(f'    ERROR snapshot: {e}')
    print(f'  {len(rows)} snapshots guardados.')

    print(f'\nTorneo re-subido correctamente. ID nuevo: {torneo_id}')
    print(f'{updated} ratings actualizados en la BD.')

# ─── MAIN ─────────────────────────────────────────────────────────────────────
def main():
    if '--list' in sys.argv:
        list_torneos()
        return

    filtro = next((a for a in sys.argv[1:] if not a.startswith('--')), None)

    # Listar y elegir torneo a limpiar
    torneos = sb_get('torneos', '?select=id,nombre,fecha&order=id.desc&limit=20')
    if not torneos:
        print('No hay torneos en la base de datos.')
        return

    torneo = None
    if filtro:
        torneo = next((t for t in torneos if filtro.lower() in t['nombre'].lower()), None)
        if not torneo:
            print(f'No se encontro torneo con nombre "{filtro}".')
            list_torneos()
            return
    else:
        torneo = torneos[0]

    print(f'\nTorneo seleccionado: [{torneo["id"]}] {torneo["nombre"]} ({torneo["fecha"]})')

    confirm = input('\nEsto borrara todos los partidos y revertira los ratings. Continuar? (s/N): ')
    if confirm.strip().lower() != 's':
        print('Cancelado.')
        return

    # 1. Limpiar
    ratings_iniciales = limpiar_torneo(torneo['id'], torneo['nombre'])

    # 2. Cargar CSV
    print(f'\nCargando CSV {CSV_FILE}...')
    matches = load_csv()
    print(f'  {len(matches)} partidos en el CSV.')

    # 3. Re-subir con logica correcta
    resubir(matches, ratings_iniciales)

if __name__ == '__main__':
    main()
