#!/usr/bin/env python3
"""
Diagnóstico de ratings post-torneo.

Preguntas que responde:
  1. ¿Cuál era el rating en la tabla jugadores ANTES del torneo?
  2. ¿Qué rating se usó en la comparación de cada partido (rating_a_antes)?
  3. ¿Hay discrepancia entre jugadores y lo guardado en partidos?
  4. ¿Los puntos calculados con esos ratings coinciden con lo guardado?
  5. ¿El sistema fue dinámico o estático?

Uso:
  python3 diagnostico_ratings.py                  # último torneo
  python3 diagnostico_ratings.py "Nombre torneo"  # torneo específico
"""

import sys
import requests
from collections import defaultdict

# ─── CONFIG ───────────────────────────────────────────────────────────────────
SUPABASE_URL = 'https://qrvyfdpwtearfpjruwja.supabase.co'
SUPABASE_KEY = 'sb_publishable_mM59efPqpcgrR3g3_6F_Ww_h1jg4PyV'

HEADERS = {
    'apikey':        SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type':  'application/json',
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

def expected_pts(rA, rB, winner):
    diff = abs(rA - rB)
    row  = next(r for r in POINT_TABLE if diff <= r['maxDiff'])
    a_is_fav = rA >= rB
    if winner == 'A':
        pts = row['fav'] if a_is_fav else row['underdog']
        return pts, -pts
    else:
        pts = row['underdog'] if a_is_fav else row['fav']
        return -pts, pts

def fp(n):   # format pts
    return f'+{n}' if n >= 0 else str(n)

def col(text, width):
    return str(text)[:width].ljust(width)

# ─── CARGA DE DATOS ───────────────────────────────────────────────────────────
def load_players():
    data = sb_get(
        'Base%20de%20Datos',
        '?select=%22Member%20ID%22,%22First%20Name%22,%22Last%20Name%22,%22Rating%22'
        '&limit=2000'
    )
    players = {}
    for p in data:
        mid = p['Member ID']
        players[mid] = {
            'name':   f"{p['First Name'] or ''} {p['Last Name'] or ''}".strip(),
            'rating': p['Rating'] or 1500,
        }
    return players

def load_torneos():
    return sb_get('torneos', '?select=id,nombre,fecha&order=id.desc&limit=20')

def load_partidos(torneo_id):
    return sb_get(
        'partidos',
        f'?torneo_id=eq.{torneo_id}'
        '&select=id,jugador_a_id,jugador_b_id,nombre_a,nombre_b,'
        'rating_a_antes,rating_b_antes,rating_a_despues,rating_b_despues,'
        'ganador,fecha'
        '&order=id.asc&limit=500'
    )

# ─── DIAGNÓSTICO PRINCIPAL ────────────────────────────────────────────────────
def run(torneo_nombre_filtro=None):
    print('\n' + '=' * 72)
    print('  DIAGNOSTICO DE RATINGS — FPRTM')
    print('=' * 72)

    torneos = load_torneos()
    if not torneos:
        print('No hay torneos en la base de datos.')
        return

    torneo = None
    if torneo_nombre_filtro:
        filtro = torneo_nombre_filtro.lower()
        torneo = next((t for t in torneos if filtro in t['nombre'].lower()), None)
        if not torneo:
            print(f'No se encontro torneo con nombre "{torneo_nombre_filtro}".')
            print('Torneos disponibles:')
            for t in torneos:
                print(f'   ID {t["id"]}: {t["nombre"]} ({t["fecha"]})')
            return
    else:
        torneo = torneos[0]

    print(f'\nTorneo : {torneo["nombre"]}')
    print(f'Fecha  : {torneo["fecha"]}')
    print(f'ID     : {torneo["id"]}')

    print('\nCargando datos...')
    players  = load_players()
    partidos = load_partidos(torneo['id'])

    if not partidos:
        print('No hay partidos registrados para este torneo.')
        return

    print(f'   {len(players)} jugadores en BD | {len(partidos)} partidos')

    # ── SECCION 1: Rating BD actual vs. rating usado como base ───────────────
    # "rating usado como base" = el rating_a_antes del PRIMER partido de ese jugador
    primer_rating = {}   # mid -> rating base que el sistema usó
    for p in partidos:
        if p['jugador_a_id'] and p['jugador_a_id'] not in primer_rating:
            primer_rating[p['jugador_a_id']] = p['rating_a_antes']
        if p['jugador_b_id'] and p['jugador_b_id'] not in primer_rating:
            primer_rating[p['jugador_b_id']] = p['rating_b_antes']

    print('\n' + '-' * 72)
    print('SECCION 1 — Rating actual en BD vs. Rating base usado por el sistema')
    print('-' * 72)
    print(f'{"ID":>7}  {"Nombre":<28} {"BD actual":>10} {"Base usada":>11}  {"Diferencia":>11}')
    print('-' * 72)

    for mid in sorted(primer_rating.keys()):
        jugador   = players.get(mid)
        nombre    = jugador['name'] if jugador else f'(ID {mid})'
        bd_actual = jugador['rating'] if jugador else '???'
        base      = primer_rating[mid]
        diff      = (bd_actual - base) if isinstance(bd_actual, int) else '?'
        diff_s    = fp(diff) if isinstance(diff, int) else '?'
        nota      = '  <- delta total' if isinstance(diff, int) and diff != 0 else ''
        print(f'{mid:>7}  {col(nombre,28)} {str(bd_actual):>10} {str(base):>11}  {diff_s:>11}{nota}')

    # ── SECCION 2: Verificacion de puntos partido a partido ──────────────────
    print('\n' + '-' * 72)
    print('SECCION 2 — Verificacion de puntos por partido')
    print('-' * 72)
    print(f'{"#":>3}  {"Jugador A":<22} {"Jugador B":<22} {"G":>2}  {"D":>4}  '
          f'{"rA":>7} {"rB":>7}  {"ExpA":>5} {"GrdA":>5}  {"ExpB":>5} {"GrdB":>5}  {"OK?":>6}')
    print('-' * 72)

    errores = []
    ok_count = 0

    for i, p in enumerate(partidos, 1):
        rA = p['rating_a_antes']
        rB = p['rating_b_antes']
        rA_d = p['rating_a_despues']
        rB_d = p['rating_b_despues']
        ganador = (p.get('ganador') or '').upper()

        guard_a = (rA_d - rA) if (rA_d is not None and rA is not None) else None
        guard_b = (rB_d - rB) if (rB_d is not None and rB is not None) else None

        if rA is not None and rB is not None and ganador in ('A', 'B'):
            exp_a, exp_b = expected_pts(rA, rB, ganador)
        else:
            exp_a = exp_b = None

        match_ok = (exp_a == guard_a and exp_b == guard_b)
        if match_ok:
            ok_count += 1
            flag = 'OK'
        else:
            flag = 'DIFF!'
            errores.append({
                'n': i,
                'nA': p.get('nombre_a', f'#{p["jugador_a_id"]}'),
                'nB': p.get('nombre_b', f'#{p["jugador_b_id"]}'),
                'ganador': ganador,
                'rA': rA, 'rB': rB,
                'exp_a': exp_a, 'exp_b': exp_b,
                'guard_a': guard_a, 'guard_b': guard_b,
            })

        d = abs(rA - rB) if (rA and rB) else '?'
        nA = col(p.get('nombre_a', f'#{p["jugador_a_id"]}'), 22)
        nB = col(p.get('nombre_b', f'#{p["jugador_b_id"]}'), 22)
        ea = fp(exp_a)   if exp_a   is not None else '?'
        eb = fp(exp_b)   if exp_b   is not None else '?'
        ga = fp(guard_a) if guard_a is not None else '?'
        gb = fp(guard_b) if guard_b is not None else '?'

        print(f'{i:>3}  {nA} {nB} {ganador:>2}  {str(d):>4}  '
              f'{str(rA):>7} {str(rB):>7}  {ea:>5} {ga:>5}  {eb:>5} {gb:>5}  {flag:>6}')

    # ── SECCION 3: ¿Dinamico o estático? ─────────────────────────────────────
    print('\n' + '-' * 72)
    print('SECCION 3 — Dinamico vs. Estatico: ¿el sistema cambio el rating entre partidos?')
    print('-' * 72)

    ratings_por_jugador = defaultdict(list)
    for i, p in enumerate(partidos, 1):
        if p['jugador_a_id']:
            ratings_por_jugador[p['jugador_a_id']].append(
                (i, p['rating_a_antes'], p.get('nombre_a', ''))
            )
        if p['jugador_b_id']:
            ratings_por_jugador[p['jugador_b_id']].append(
                (i, p['rating_b_antes'], p.get('nombre_b', ''))
            )

    jugadores_dinamicos = []
    for mid, entradas in sorted(ratings_por_jugador.items()):
        if len(entradas) < 2:
            continue
        ratings_usados = [e[1] for e in entradas]
        nombre = entradas[0][2]
        if len(set(ratings_usados)) > 1:
            jugadores_dinamicos.append(mid)
            print(f'  DINAMICO  #{mid} {nombre}:')
            for n, r, _ in entradas:
                print(f'    Partido #{n}: rating usado = {r}')
        else:
            print(f'  ESTATICO  #{mid} {col(nombre,28)} base={ratings_usados[0]}  ({len(entradas)} partidos)')

    # ── RESUMEN ───────────────────────────────────────────────────────────────
    print('\n' + '=' * 72)
    print('RESUMEN FINAL')
    print('=' * 72)
    print(f'  Partidos analizados : {len(partidos)}')
    print(f'  Puntos correctos    : {ok_count}')
    print(f'  Discrepancias       : {len(errores)}')

    if jugadores_dinamicos:
        print(f'\n  PROBLEMA: {len(jugadores_dinamicos)} jugador(es) con rating DINAMICO.')
        print('  Esto significa que los partidos guardados en la BD usaron ratings')
        print('  que iban cambiando partido a partido (anterior al fix de rating estatico).')
        print('  Hay que reprocesar el torneo para corregirlo.')
    else:
        print('\n  CALCULO: rating ESTATICO (correcto).')
        print('  Todos los partidos de cada jugador usaron el mismo rating base.')

    if errores:
        print(f'\n  PARTIDOS CON PTS INCORRECTOS ({len(errores)}):')
        for e in errores:
            print(f'    #{e["n"]:>3} {e["nA"]} vs {e["nB"]} (ganador {e["ganador"]})')
            d = abs(e["rA"] - e["rB"]) if e["rA"] and e["rB"] else "?"
            print(f'         D={d}  Esperado A={fp(e["exp_a"])} B={fp(e["exp_b"])}  '
                  f'Guardado A={fp(e["guard_a"])} B={fp(e["guard_b"])}')
    else:
        print('\n  Todos los puntos guardados coinciden con la tabla de distribucion.')

    print()

if __name__ == '__main__':
    filtro = sys.argv[1] if len(sys.argv) > 1 else None
    run(filtro)
