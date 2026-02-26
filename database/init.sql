-- ============================================================
-- 1. TABLAS MAESTRAS (dimensiones)
-- ============================================================

CREATE TABLE IF NOT EXISTS league (
    league_id VARCHAR(50) PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    country   VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS season (
    season_id VARCHAR(50) PRIMARY KEY,
    name      VARCHAR(50)  NOT NULL,
    league_id VARCHAR(50)  REFERENCES league(league_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS team (
    team_id VARCHAR(50) PRIMARY KEY,
    name    VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS player (
    player_id VARCHAR(50) PRIMARY KEY,
    name      VARCHAR(150) NOT NULL
);

-- ============================================================
-- 2. TABLA DE PARTIDOS
-- ============================================================

CREATE TABLE IF NOT EXISTS match (
    event_id     VARCHAR(50) PRIMARY KEY,
    season_id    VARCHAR(50) REFERENCES season(season_id),
    status       VARCHAR(50),
    home_team_id VARCHAR(50) REFERENCES team(team_id),
    away_team_id VARCHAR(50) REFERENCES team(team_id)
);

-- ============================================================
-- 3. CATÁLOGO DE MÉTRICAS (patrón EAV)
-- En vez de tener 50 columnas en las tablas de hechos,
-- guardamos cada métrica como una fila con su nombre y valor.
-- ============================================================

CREATE TABLE IF NOT EXISTS statistics (
    statistic_id SERIAL      PRIMARY KEY,
    slug         VARCHAR(100) UNIQUE NOT NULL,   
    display_name VARCHAR(150) NOT NULL          
);

-- ============================================================
-- 4. TABLAS DE HECHOS (fact tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS team_statistics (
    stat_record_id SERIAL      PRIMARY KEY,
    event_id       VARCHAR(50) REFERENCES match(event_id) ON DELETE CASCADE,
    team_id        VARCHAR(50) REFERENCES team(team_id),
    statistic_id   INTEGER     REFERENCES statistics(statistic_id),
    value          FLOAT       NOT NULL,
    UNIQUE(event_id, team_id, statistic_id)
);

-- team_id indica a qué equipo pertenecía el jugador en ese partido
CREATE TABLE IF NOT EXISTS player_statistics (
    stat_record_id SERIAL      PRIMARY KEY,
    event_id       VARCHAR(50) REFERENCES match(event_id) ON DELETE CASCADE,
    player_id      VARCHAR(50) REFERENCES player(player_id),
    team_id        VARCHAR(50) REFERENCES team(team_id),
    statistic_id   INTEGER     REFERENCES statistics(statistic_id),
    value          FLOAT       NOT NULL,
    UNIQUE(event_id, player_id, statistic_id)
);

-- ============================================================
-- ÍNDICES para consultas rápidas
-- ============================================================
CREATE INDEX idx_match_season       ON match(season_id);
CREATE INDEX idx_match_teams        ON match(home_team_id, away_team_id);
CREATE INDEX idx_team_stats_event   ON team_statistics(event_id);
CREATE INDEX idx_player_stats_event ON player_statistics(event_id);
CREATE INDEX idx_player_stats_team  ON player_statistics(team_id);
CREATE INDEX idx_stats_slug         ON statistics(slug);
