{{ config(
    materialized = 'table'
) }}

-- ==========================================================
-- Model: fct_trips
-- Description: Gold layer fact table containing deduplicated,
-- enriched trip-level data for CitiBike analytics.
-- ==========================================================

WITH source_trips AS (
    SELECT
        bikeid,
        starttime,
        stoptime,
        tripduration,
        start_station_id,
        end_station_id,
        usertype,
        birth_year,
        gender,
        start_latitude,
        start_longitude,
        end_latitude,
        end_longitude,

        -- Generate deterministic source-level key for deduplication
        HASH(
            starttime,
            bikeid,
            start_station_id,
            end_station_id,
            tripduration
        ) AS source_trip_key

    FROM {{ ref('stg_citibike_trips') }}
    WHERE starttime IS NOT NULL
),

deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY source_trip_key
            ORDER BY
                starttime ASC,
                stoptime ASC,
                tripduration DESC
        ) AS rn
    FROM source_trips
),

unique_trips AS (
    SELECT
        -- Generate final surrogate key for each trip
        HASH(source_trip_key, rn) AS trip_id,
        bikeid,
        starttime,
        stoptime,
        tripduration,
        start_station_id,
        end_station_id,
        usertype,
        birth_year,
        gender,
        start_latitude,
        start_longitude,
        end_latitude,
        end_longitude
    FROM deduplicated
    WHERE rn = 1
),

enriched_trips AS (
    SELECT
        trip_id,
        bikeid,

        -- Core trip timing
        starttime,
        stoptime,
        tripduration,

        -- Optimized temporal enrichments using DATE_PART for performance
        DATE_PART('hour', starttime) AS start_hour,
        DATE_PART('day', starttime) AS start_day,
        DATE_PART('month', starttime) AS start_month,
        DATE_PART('year', starttime) AS start_year,
        TO_VARCHAR(starttime, 'DY') AS day_of_week,
        CASE
            WHEN TO_VARCHAR(starttime, 'DY') IN ('Sat', 'Sun') THEN 'Weekend'
            ELSE 'Weekday'
        END AS weekend_indicator,

        -- Station references
        start_station_id,
        end_station_id,

        -- User demographics
        usertype,
        birth_year,
        CASE
            WHEN birth_year IS NOT NULL THEN YEAR(CURRENT_DATE()) - birth_year
        END AS age,
        gender,

        -- Geolocation details
        start_latitude,
        start_longitude,
        end_latitude,
        end_longitude

    FROM unique_trips
)

SELECT * FROM enriched_trips
