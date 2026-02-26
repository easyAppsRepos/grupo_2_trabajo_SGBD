import pandas as pd
from sqlalchemy import create_engine, text
import os
import time

def load_data():
    print("\n" + "="*50)
    print("  CARGA DE DATOS - Grupo 2 SGBD")
    print("="*50)

    # --- CONEXIÓN A LA BASE DE DATOS ---
    # Leemos las credenciales desde variables de entorno (definidas en docker-compose.yml)
    dbname   = os.getenv("POSTGRES_DB", "soccer_stats")
    user     = os.getenv("POSTGRES_USER", "user_master")
    password = os.getenv("POSTGRES_PASSWORD", "password_master")
    host     = os.getenv("POSTGRES_HOST", "postgres")
    port     = os.getenv("POSTGRES_PORT", "5432")

    conn_str = f"postgresql://{user}:{password}@{host}:{port}/{dbname}"
    engine = create_engine(conn_str)

    # Esperamos a que la BD esté lista (puede tardar unos segundos al arrancar Docker)
    print("\n[1/6] Esperando a que la base de datos este lista...")
    for _ in range(15):
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            print("  OK  Base de datos lista!")
            break
        except Exception:
            time.sleep(5)
    else:
        print("  ERROR  No se pudo conectar a la base de datos.")
        return

    # --- CARGA DE CSVs ---
    print("\n[2/6] Leyendo archivos CSV...")
    team_df   = pd.read_csv("/data/team_statistics.csv", low_memory=False)
    player_df = pd.read_csv("/data/player_statistics.csv", low_memory=False)

    # Limpiamos los IDs quitando espacios en blanco
    for df in [team_df, player_df]:
        for col in ['event_id', 'team_id', 'league_id', 'season_id']:
            if col in df.columns:
                df[col] = df[col].astype(str).str.strip()
    if 'player_id' in player_df.columns:
        player_df['player_id'] = player_df['player_id'].astype(str).str.strip()

    # Insertamos primero los datos de referencia: ligas, temporadas, equipos, jugadores
    # Usamos ON CONFLICT DO NOTHING para que sea seguro ejecutar esto varias veces
    print("\n[3/6] Insertando datos maestros (ligas, temporadas, equipos, jugadores)...")
    with engine.begin() as conn:

        # Ligas únicas del CSV
        for lid in team_df['league_id'].dropna().unique():
            conn.execute(text("INSERT INTO league (league_id, name, country) VALUES (:id, 'LaLiga', 'Spain') ON CONFLICT DO NOTHING"), {"id": lid})

        # Temporadas únicas del CSV (necesitan ligar con una liga)
        seasons = team_df[['season_id', 'season_name', 'league_id']].dropna(subset=['season_id', 'league_id']).drop_duplicates()
        for _, row in seasons.iterrows():
            conn.execute(
                text("INSERT INTO season (season_id, name, league_id) VALUES (:id, :name, :lid) ON CONFLICT DO NOTHING"),
                {"id": row['season_id'], "name": row['season_name'], "lid": row['league_id']}
            )

        # Equipos (combinamos los de ambos CSVs para no perder ninguno)
        teams = pd.concat([
            team_df[['team_id', 'team_name']],
            player_df[['team_id', 'team_name']]
        ]).dropna(subset=['team_id']).drop_duplicates(subset=['team_id'])
        for _, row in teams.iterrows():
            conn.execute(
                text("INSERT INTO team (team_id, name) VALUES (:id, :name) ON CONFLICT DO NOTHING"),
                {"id": row['team_id'], "name": row['team_name']}
            )

        # Jugadores únicos del CSV de jugadores
        players = player_df[['player_id', 'player_name']].dropna(subset=['player_id']).drop_duplicates()
        for _, row in players.iterrows():
            conn.execute(
                text("INSERT INTO player (player_id, name) VALUES (:id, :name) ON CONFLICT DO NOTHING"),
                {"id": row['player_id'], "name": row['player_name']}
            )

        # ==========================================================================
        # PASO 2: PARTIDOS
        # Cada partido (event_id) tiene un equipo local y uno visitante
        # ==========================================================================
        print("\n[4/6] Insertando partidos...")
        matches = team_df.drop_duplicates(subset=['event_id'])[['event_id', 'season_id']].copy()
        matches['season_id'] = matches['season_id'].fillna('N/A')

        for _, row in matches.iterrows():
            eid = row['event_id']
            home_ids = team_df[(team_df['event_id'] == eid) & (team_df['team_qualifier'] == 'home')]['team_id'].values
            away_ids = team_df[(team_df['event_id'] == eid) & (team_df['team_qualifier'] == 'away')]['team_id'].values
            conn.execute(
                text("INSERT INTO match (event_id, season_id, home_team_id, away_team_id, status) VALUES (:eid, :sid, :hid, :aid, 'closed') ON CONFLICT DO NOTHING"),
                {
                    "eid": eid,
                    "sid": row['season_id'],
                    "hid": home_ids[0] if len(home_ids) > 0 else None,
                    "aid": away_ids[0] if len(away_ids) > 0 else None,
                }
            )

    # ==========================================================================
    # PASO 3: CATÁLOGO DE ESTADÍSTICAS
    # Identificamos cuáles columnas son métricas reales (numéricas) y cuáles son metadatos
    # Las métricas se guardan en la tabla 'statistics' (patrón EAV)
    # ==========================================================================
    print("\n[5/6] Catalogando metricas (slugs de estadisticas)...")
    # Columnas que NO son estadísticas (son identificadores o metadatos)
    cols_meta = {
        'event_id', 'team_id', 'player_id', 'team_name', 'player_name',
        'team_qualifier', 'event_status', 'match_status', 'league_id',
        'season_id', 'season_name', 'starter', 'position'
    }

    t_metrics = [c for c in team_df.columns   if c not in cols_meta]
    p_metrics = [c for c in player_df.columns if c not in cols_meta]
    all_metrics = sorted(set(t_metrics) | set(p_metrics))

    with engine.begin() as conn:
        for slug in all_metrics:
            conn.execute(
                text("INSERT INTO statistics (slug, display_name) VALUES (:slug, :name) ON CONFLICT DO NOTHING"),
                {"slug": slug, "name": slug.replace('_', ' ').title()}
            )

    # Cargamos el mapa slug -> statistic_id para usarlo al insertar hechos
    db_stats = pd.read_sql("SELECT statistic_id, slug FROM statistics", engine)
    slug_map = dict(zip(db_stats['slug'], db_stats['statistic_id']))

    # ==========================================================================
    # PASO 4: TABLAS DE HECHOS (fact tables)
    # Aquí es donde guardamos las estadísticas reales de equipos y jugadores.
    # Usamos melt() para transformar el CSV ancho (una columna por métrica)
    # a formato largo (una fila por métrica), que es lo que requiere el modelo EAV.
    # ==========================================================================
    print("\n[6/6] Cargando estadisticas en tablas de hechos...")
    # Solo insertamos estadísticas de partidos que realmente existen en la BD
    valid_events = set(pd.read_sql("SELECT event_id FROM match", engine)['event_id'])

    # --- Estadísticas de equipo ---
    t_melted = team_df.melt(id_vars=['event_id', 'team_id'], value_vars=t_metrics).dropna(subset=['value'])
    t_melted['value'] = pd.to_numeric(t_melted['value'], errors='coerce')
    t_melted = t_melted.dropna(subset=['value'])
    t_melted = t_melted[t_melted['event_id'].isin(valid_events)]
    t_melted['statistic_id'] = t_melted['variable'].map(slug_map)
    t_melted = t_melted.dropna(subset=['statistic_id'])
    t_melted = t_melted.drop_duplicates(subset=['event_id', 'team_id', 'statistic_id'])

    print(f"  -> team_statistics:   {len(t_melted)} filas")
    t_melted[['event_id', 'team_id', 'statistic_id', 'value']].to_sql(
        'team_statistics', engine, if_exists='append', index=False, chunksize=1000, method='multi'
    )

    # --- Estadísticas de jugador ---
    # Incluimos team_id para saber a qué equipo pertenecía el jugador en ese partido
    p_melted = player_df.melt(id_vars=['event_id', 'player_id', 'team_id'], value_vars=p_metrics).dropna(subset=['value'])
    p_melted['value'] = pd.to_numeric(p_melted['value'], errors='coerce')
    p_melted = p_melted.dropna(subset=['value'])
    p_melted = p_melted[p_melted['event_id'].isin(valid_events)]
    p_melted['statistic_id'] = p_melted['variable'].map(slug_map)
    p_melted = p_melted.dropna(subset=['statistic_id'])
    p_melted = p_melted.drop_duplicates(subset=['event_id', 'player_id', 'statistic_id'])

    print(f"  -> player_statistics: {len(p_melted)} filas")
    p_melted[['event_id', 'player_id', 'team_id', 'statistic_id', 'value']].to_sql(
        'player_statistics', engine, if_exists='append', index=False, chunksize=1000, method='multi'
    )

    print("\n" + "="*50)
    print("  LISTO! Datos cargados correctamente.")
    print("="*50 + "\n")

if __name__ == "__main__":
    load_data()
