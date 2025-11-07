{{ config(
    materialized = 'table',
    unique_key = 'station_id'
) }}

WITH start_stations AS (
    SELECT
        start_station_id AS station_id,
        start_station_name AS station_name,
        start_latitude AS latitude,
        start_longitude AS longitude
    FROM {{ ref('stg_citibike_trips') }}
    WHERE start_station_id IS NOT NULL
),

end_stations AS (
    SELECT
        end_station_id AS station_id,
        end_station_name AS station_name,
        end_latitude AS latitude,
        end_longitude AS longitude
    FROM {{ ref('stg_citibike_trips') }}
    WHERE end_station_id IS NOT NULL
),

all_stations AS (
    SELECT * FROM start_stations
    UNION
    SELECT * FROM end_stations
),

deduplicated_stations AS (
    SELECT
        station_id,
        station_name,
        latitude,
        longitude,
        ROW_NUMBER() OVER (PARTITION BY station_id ORDER BY station_name) AS rn
    FROM all_stations
    WHERE station_id IS NOT NULL
)

SELECT
    station_id,
    station_name,
    latitude,
    longitude
FROM deduplicated_stations
WHERE rn = 1