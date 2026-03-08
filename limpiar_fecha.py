#!/usr/bin/env python3
"""
Revierte TODOS los torneos de una fecha y restaura los ratings pre-evento.
Procesa los torneos en orden inverso (más nuevo primero) para deshacer
correctamente la cadena de actualizaciones.

Uso:
  python3 limpiar_fecha.py 2026-03-08           # revertir todo ese día
  python3 limpiar_fecha.py 2026-03-08 --dry-run # solo mostrar qué haría
"""

import sys
import requests

SUPABASE_URL = 'https://qrvyfdpwtearfpjruwja.supabase.co'
SUPABASE_KEY = 'sb_publishable_mM59efPqpcgrR3g3_6F_Ww_h1jg4PyV'

HEADERS = {
    'apikey':        SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type':  'application/json',
    'Prefer':        'return=representation',
}

def sb_get(table, params=''):
    r = requests.get(f'{SUPABASE_URL}/rest/v1/{table}{params}', headers=HEADERS)
    r.raise_for_status()
    return r.json()

def sb_patch(table, query, body):
    r = requests.patch(f'{SUPABASE_URL}/rest/v1/{table}?{query}', headers=HEADERS, json=body)
    r.raise_for_status()
    return r.json()

def sb_delete(table, query):
    r = requests.delete(f'{SUPABASE_URL}/rest/v1/{table}?{query}', headers=HEADERS)
    r.raise_for_status()

def main():
    args = sys.argv[1:]
    dry_run = '--dry-run' in args
    fecha_args = [a for a in args if not a.startswith('--')]

    if not fecha_args:
        print('Uso: python3 limpiar_fecha.py YYYY-MM-DD [--dry-run]')
        sys.exit(1)

    fecha = fecha_args[0]
    print(f'{"[DRY RUN] " if dry_run else ""}Buscando torneos del {fecha}...')

    torneos = sb_get('torneos', f'?fecha=eq.{fecha}&select=id,nombre,fecha&order=id.desc')
    if not torneos:
        print(f'No se encontraron torneos con fecha {fecha}.')
        sys.exit(0)

    print(f'\nTorneos encontrados ({len(torneos)}), se procesarán en orden inverso:')
    for t in torneos:
        pts = sb_get('partidos', f'?torneo_id=eq.{t["id"]}&select=id')
        print(f'  ID {t["id"]:>4}: {t["nombre"]}  [{len(pts)} partidos]')

    if not dry_run:
        confirm = input(f'\nEsto revertirá {len(torneos)} torneo(s) y restaurará los ratings pre-evento. Continuar? (s/N): ')
        if confirm.strip().lower() != 's':
            print('Cancelado.')
            sys.exit(0)

    # Procesar en orden inverso (ID más alto primero = más reciente)
    ratings_revertidos = {}   # mid → rating pre-evento (reconstruido)
    total_torneos_borrados = 0

    for torneo in torneos:  # ya vienen en order=id.desc
        tid  = torneo['id']
        nombre = torneo['nombre']
        print(f'\n{"[DRY RUN] " if dry_run else ""}Revirtiendo: [{tid}] {nombre}')

        # Obtener rating_antes de cada jugador en este torneo
        partidos = sb_get('partidos',
            f'?torneo_id=eq.{tid}'
            '&select=jugador_a_id,jugador_b_id,rating_a_antes,rating_b_antes')

        # El primer partido de cada jugador en este torneo tiene su rating
        # al momento en que este torneo fue subido
        jugadores_este_torneo = {}
        for p in partidos:
            for (mid, rating_antes) in [
                (p['jugador_a_id'], p['rating_a_antes']),
                (p['jugador_b_id'], p['rating_b_antes']),
            ]:
                if mid and mid not in jugadores_este_torneo:
                    jugadores_este_torneo[mid] = rating_antes

        print(f'  Jugadores en este torneo: {len(jugadores_este_torneo)}')

        # Revertir ratings en BD (solo si no los hemos revertido con un torneo más nuevo)
        revertidos = 0
        for mid, rating_pre_este_torneo in jugadores_este_torneo.items():
            # Guardar el rating más antiguo que encontramos para cada jugador
            # (el del torneo más antiguo del día, ya que procesamos de nuevo a viejo)
            ratings_revertidos[mid] = rating_pre_este_torneo

            if not dry_run:
                try:
                    sb_patch('Base%20de%20Datos',
                             f'%22Member%20ID%22=eq.{mid}',
                             {'New Rating': rating_pre_este_torneo})
                    revertidos += 1
                except Exception as e:
                    print(f'    ERROR revirtiendo #{mid}: {e}')
            else:
                revertidos += 1

        print(f'  {"[DRY RUN] " if dry_run else ""}{revertidos} ratings revertidos.')

        if not dry_run:
            # Borrar partidos, resultados_evento y el torneo
            try:
                sb_delete('partidos', f'torneo_id=eq.{tid}')
                print(f'  Partidos borrados.')
            except Exception as e:
                print(f'  ERROR borrando partidos: {e}')
            try:
                sb_delete('resultados_evento', f'id_torneo=eq.{tid}')
                print(f'  resultados_evento borrados.')
            except Exception as e:
                print(f'  ERROR borrando resultados_evento: {e}')
            try:
                sb_delete('torneos', f'id=eq.{tid}')
                print(f'  Registro torneo borrado.')
            except Exception as e:
                print(f'  ERROR borrando torneo: {e}')

        total_torneos_borrados += 1

    print(f'\n{"=" * 60}')
    print(f'{"[DRY RUN] " if dry_run else ""}Limpieza completada.')
    print(f'  Torneos revertidos: {total_torneos_borrados}')
    print(f'  Jugadores restaurados: {len(ratings_revertidos)}')
    print(f'\nRatings pre-evento restaurados:')
    for mid, r in sorted(ratings_revertidos.items()):
        print(f'  #{mid}: {r}')
    print(f'\nAhora puedes re-subir los torneos del día desde la web')
    print(f'(la sesión usará estos ratings como base automáticamente).')

if __name__ == '__main__':
    main()
