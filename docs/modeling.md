# Documentación de Modelado de Datos - Grupo 2

Este documento detalla el diseño de la base de datos para el proyecto de la materia SGBD. Siguiendo principios avanzados de diseño de bases de datos para Big Data.

## 1. Modelo Entidad-Relación (ER)

### Diagrama

```mermaid
erDiagram
    LEAGUE ||--o{ SEASON : "contiene"
    SEASON ||--o{ MATCH : "tiene"
    TEAM ||--o{ MATCH : "local"
    TEAM ||--o{ MATCH : "visitante"
    MATCH ||--o{ TEAM_STATISTICS : "registra"
    TEAM ||--o{ TEAM_STATISTICS : "participa"
    MATCH ||--o{ PLAYER_STATISTICS : "registra"
    PLAYER ||--o{ PLAYER_STATISTICS : "tiene"
    TEAM ||--o{ PLAYER_STATISTICS : "pertenece_en_partido"
    STATISTICS ||--o{ TEAM_STATISTICS : "define"
    STATISTICS ||--o{ PLAYER_STATISTICS : "define"

    LEAGUE {
        string league_id PK
        string name
        string country
    }

    SEASON {
        string season_id PK
        string name
        string league_id FK
    }

    TEAM {
        string team_id PK
        string name
    }

    PLAYER {
        string player_id PK
        string name
    }

    MATCH {
        string event_id PK
        string season_id FK
        string status
        string home_team_id FK
        string away_team_id FK
    }

    STATISTICS {
        int statistic_id PK
        string slug "e.g. shots_total"
        string display_name "e.g. Total Shots"
    }

    TEAM_STATISTICS {
        int stat_record_id PK
        string event_id FK
        string team_id FK
        int statistic_id FK
        float value
    }

    PLAYER_STATISTICS {
        int stat_record_id PK
        string event_id FK
        string player_id FK
        string team_id FK
        int statistic_id FK
        float value
    }
```

## 2. Arquitectura del Modelo y Justificación

### Flexibilidad Dinámica (EAV Pattern)
En lugar de añadir columnas nuevas cada vez que las APIs evolucionan (ej. xG, expected assists), el modelo utiliza la tabla `STATISTICS` como catálogo. Este enfoque resuelve el problema de columnas vacías y permite que el esquema sea extensible sin modificar la estructura física de las tablas.

### Normalización y Granularidad
Se ha aplicado una normalización de alto nivel para separar datos maestros de hechos transaccionales. Las tablas de "Performance" están separadas por sujeto (Team vs Player) para optimizar el particionamiento e indexación en consultas masivas.

`PLAYER_STATISTICS` incluye `team_id` para saber a qué equipo pertenecía el jugador en el contexto de ese partido (ya que un jugador puede cambiar de equipo entre temporadas).

### Selección de Tecnología: PostgreSQL
Hemos seleccionado **PostgreSQL** basándonos en los siguientes pilares de nuestro Master:
- **Integridad Deportiva**: Soporte total de ACID para garantizar que las cargas de partidos sean atómicas y consistentes.
- **Evolución del Esquema**: Facilidad para manejar el catálogo de estadísticas dinámicas.
- **Escalabilidad**: Capacidades de indexación GIN/B-Tree y particionamiento nativo.
- **Viabilidad Local**: Contenerización sencilla para entornos de desarrollo y evaluación.

### Pipeline de Ingesta (ETL)
Para la carga de los datos históricos de Sportradar, hemos implementado una capa de **Loader** automatizada que:
1.  **Validación**: Verifica la preparación del SGBD antes de iniciar la ingesta.
2.  **Transformación**: Realiza un "melting" de los DataFrames anchos (CSV) a un formato largo compatible con el modelo EAV.
3.  **Carga Atómica**: Inserta las dimensiones maestras (Leagues, Teams, Players) seguidas de los hechos (Statistics) preservando la integridad referencial.
4.  **Idempotencia**: Diseñado para ser ejecutado múltiples veces sin duplicar registros, facilitando procesos de recuperación ante desastres (DR) y actualizaciones parciales.

---
*Documentación técnica - Master en Big Data & Business Intelligence*
