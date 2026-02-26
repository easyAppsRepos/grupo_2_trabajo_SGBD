-- Catálogo de métricas disponibles
-- Muestra todas las estadísticas que tenemos y si aplican a equipo, jugador o ambos
SELECT
    statistic_id,
    slug          AS clave_interna,
    display_name  AS nombre_legible,
    subject_type  AS aplica_a
FROM statistics
ORDER BY subject_type, slug;

-- Top 10 equipos con más goles (global)
-- Solo cambiamos el slug de la métrica para obtener el ranking que queramos
SELECT
    t.name            AS equipo,
    SUM(ts.value)     AS goles_totales
FROM team_statistics ts
JOIN statistics      st ON st.statistic_id = ts.statistic_id
JOIN team            t  ON t.team_id       = ts.team_id
WHERE st.slug = 'score'
GROUP BY t.name
ORDER BY goles_totales DESC
LIMIT 10;


-- Media de posesión local vs visitante por equipo
-- Queremos ver si los equipos tienen más posesión cuando juegan en casa
SELECT
    t.name                           AS equipo,
    ROUND(AVG(CASE WHEN m.home_team_id = ts.team_id
                   THEN ts.value END)::numeric, 2)  AS posesion_media_local,
    ROUND(AVG(CASE WHEN m.away_team_id = ts.team_id
                   THEN ts.value END)::numeric, 2)  AS posesion_media_visitante
FROM team_statistics ts
JOIN statistics      st ON st.statistic_id = ts.statistic_id
JOIN match           m  ON m.event_id     = ts.event_id
JOIN team            t  ON t.team_id      = ts.team_id
WHERE st.slug = 'ball_possession'
GROUP BY t.name
HAVING COUNT(*) > 5
ORDER BY posesion_media_local DESC NULLS LAST;


-- Top 10 goleadores
-- Suma los goles de cada jugador en todos sus partidos
SELECT
    p.name            AS jugador,
    t.name            AS equipo,
    SUM(ps.value)     AS goles
FROM player_statistics ps
JOIN statistics        st ON st.statistic_id = ps.statistic_id
JOIN player            p  ON p.player_id     = ps.player_id
JOIN team              t  ON t.team_id       = ps.team_id
WHERE st.slug = 'goals_scored'
GROUP BY p.name, t.name
ORDER BY goles DESC
LIMIT 10;


-- Top 10 jugadores con más asistencias
SELECT
    p.name            AS jugador,
    t.name            AS equipo,
    SUM(ps.value)     AS asistencias
FROM player_statistics ps
JOIN statistics        st ON st.statistic_id = ps.statistic_id
JOIN player            p  ON p.player_id     = ps.player_id
JOIN team              t  ON t.team_id       = ps.team_id
WHERE st.slug = 'assists'
GROUP BY p.name, t.name
ORDER BY asistencias DESC
LIMIT 10;


-- Ventaja de jugar en casa: tiros y posesión local vs visitante
-- Usamos FILTER para separar las medias según si el equipo era local o visitante
SELECT
    st.display_name                                            AS metrica,
    ROUND(AVG(ts.value) FILTER
          (WHERE ts.team_id = m.home_team_id)::numeric, 2)    AS media_local,
    ROUND(AVG(ts.value) FILTER
          (WHERE ts.team_id = m.away_team_id)::numeric, 2)    AS media_visitante
FROM team_statistics ts
JOIN statistics      st ON st.statistic_id = ts.statistic_id
JOIN match           m  ON m.event_id     = ts.event_id
WHERE st.slug IN ('shots_total', 'ball_possession')
GROUP BY st.display_name
ORDER BY st.display_name;


-- Resumen de todas las estadísticas de un jugador
-- Muestra cuánto sumó en cada métrica y en cuántos partidos tuvo datos
SELECT
    st.display_name  AS metrica,
    SUM(ps.value)    AS total,
    COUNT(*)         AS partidos_con_datos
FROM player_statistics ps
JOIN statistics        st ON st.statistic_id = ps.statistic_id
WHERE ps.player_id = 'sr:player:2439417' --Lamine Yamal
GROUP BY st.display_name
ORDER BY total DESC;


-- Ranking global de ocasiones creadas por equipo (window function)
-- Usamos RANK() para clasificar todos los equipos globalmente
SELECT
    t.name                                          AS equipo,
    ROUND(AVG(ts.value)::numeric, 2)                AS media_ocasiones_creadas,
    RANK() OVER (
        ORDER BY AVG(ts.value) DESC
    )                                               AS ranking
FROM team_statistics ts
JOIN statistics      st ON st.statistic_id = ts.statistic_id
JOIN team            t  ON t.team_id       = ts.team_id
WHERE st.slug = 'chances_created'
GROUP BY t.team_id, t.name
ORDER BY ranking;


-- Equipos que superan la media global de goles (CTE)
-- Primero calculamos la media global y luego filtramos los equipos que la superan
WITH media_global AS (
    SELECT
        AVG(ts.value)                    AS media_goles
    FROM team_statistics ts
    JOIN statistics      st ON st.statistic_id = ts.statistic_id
    WHERE st.slug = 'goals_scored'
),
goles_por_equipo AS (
    SELECT
        t.name                           AS equipo,
        AVG(ts.value)                    AS media_goles_equipo
    FROM team_statistics ts
    JOIN statistics      st ON st.statistic_id = ts.statistic_id
    JOIN team            t  ON t.team_id      = ts.team_id
    WHERE st.slug = 'goals_scored'
    GROUP BY t.name
)
SELECT
    gpe.equipo,
    ROUND(gpe.media_goles_equipo::numeric, 2)             AS media_equipo,
    ROUND(mg.media_goles::numeric, 2)                     AS media_global,
    ROUND((gpe.media_goles_equipo - mg.media_goles)::numeric, 2) AS diferencia
FROM goles_por_equipo gpe
JOIN media_global     mg ON 1 = 1
WHERE gpe.media_goles_equipo > mg.media_goles
ORDER BY diferencia DESC;
