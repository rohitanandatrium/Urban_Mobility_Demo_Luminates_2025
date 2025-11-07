{{ config(
    materialized = 'table'
) }}

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
        -- Add a unique identifier from source data if available
        {{ dbt_utils.generate_surrogate_key([
            'starttime', 
            'bikeid', 
            'start_station_id',
            'end_station_id',
            'tripduration'
        ]) }} as source_trip_key
    FROM {{ ref('stg_citibike_trips') }}
),

deduplicated_trips AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY source_trip_key 
            ORDER BY 
                starttime,
                stoptime,
                tripduration DESC  -- Prefer longer duration if duplicates exist
        ) as duplicate_rank
    FROM source_trips
),

unique_trips AS (
    SELECT
        -- Generate final trip_id only after deduplication
        {{ dbt_utils.generate_surrogate_key([
            'source_trip_key',
            'duplicate_rank'
        ]) }} as trip_id,
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
    FROM deduplicated_trips
    WHERE duplicate_rank = 1  -- Keep only the first occurrence of duplicates
),

enriched_trips AS (
    SELECT
        trip_id,
        bikeid,
        
        -- Core trip timing
        starttime,
        stoptime,
        tripduration,
        
        -- Temporal enrichments
        EXTRACT(HOUR FROM starttime) AS start_hour,
        EXTRACT(DAY FROM starttime) AS start_day,
        EXTRACT(MONTH FROM starttime) AS start_month,
        EXTRACT(YEAR FROM starttime) AS start_year,
        DAYNAME(starttime) AS day_of_week,
        CASE 
            WHEN DAYNAME(starttime) IN ('Sat', 'Sun') THEN 'Weekend'
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
            ELSE NULL
        END AS age,
        gender,
        
        -- Geolocation
        start_latitude,
        start_longitude,
        end_latitude,
        end_longitude
        
    FROM unique_trips
)

SELECT * FROM enriched_trips