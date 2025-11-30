{{
    config(
        materialized='table'
    )
}}

WITH source AS (
    SELECT
        RAW_DATA,
        FILENAME,
        FILE_ROW_NUMBER,
        FILE_MODIFIED_TIME,
        LOAD_ID,
        LOADED_AT
    FROM {{ source('bronze', 'BRONZE_CITIBIKE_TRIPS_RAW') }}
    WHERE RAW_DATA IS NOT NULL
),

parsed AS (
    SELECT
        -- 🕒 TIMESTAMP HANDLING - ALL YEARS COVERED
        CASE 
            -- 2015: "2/1/2015 0:01" format
            WHEN FILENAME LIKE '%2015%' THEN
                TRY_TO_TIMESTAMP(RAW_DATA:starttime::STRING, 'MM/DD/YYYY HH24:MI')
            -- 2024 CORRUPTED: stoptime = actual starttime
            WHEN FILENAME LIKE '2024%' THEN
                TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING)
            -- 2025 CORRECTED: stoptime = actual starttime, start_station_id = actual stoptime
            WHEN FILENAME LIKE '2025%' THEN
                TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING)
            -- ALL OTHER YEARS (2013, 2014, 2024+, 2025+)
            ELSE
                COALESCE(
                    TRY_TO_TIMESTAMP(RAW_DATA:started_at::STRING),  -- 2024+ clean
                    TRY_TO_TIMESTAMP(RAW_DATA:starttime::STRING),   -- 2013-2014
                    TRY_TO_TIMESTAMP(RAW_DATA:col2::STRING)         -- fallback
                )
        END AS starttime,

        CASE 
            -- 2015: "2/1/2015 0:14" format
            WHEN FILENAME LIKE '%2015%' THEN
                TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING, 'MM/DD/YYYY HH24:MI')
            -- 2024 CORRUPTED: start_station_id = actual stoptime
            WHEN FILENAME LIKE '2024%' THEN
                TRY_TO_TIMESTAMP(RAW_DATA:start_station_id::STRING)
            -- 2025 CORRECTED: start_station_id = actual stoptime
            WHEN FILENAME LIKE '2025%' THEN
                TRY_TO_TIMESTAMP(RAW_DATA:start_station_id::STRING)
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    TRY_TO_TIMESTAMP(RAW_DATA:ended_at::STRING),    -- 2024+ clean
                    TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING),    -- 2013-2014
                    TRY_TO_TIMESTAMP(RAW_DATA:col3::STRING)         -- fallback
                )
        END AS stoptime,

        -- 🏢 STATION DATA - UNIVERSAL MAPPING
        CASE 
            -- 2024 CORRUPTED: start_station_latitude = station ID
            WHEN FILENAME LIKE '2024%' THEN
                NULLIF(TRIM(RAW_DATA:start_station_latitude::STRING), '')
            -- 2025 CORRECTED: start_station_latitude = start station ID
            WHEN FILENAME LIKE '2025%' THEN
                NULLIF(TRIM(RAW_DATA:start_station_latitude::STRING), '')
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:start_station_id::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col4::STRING), '')
                )
        END AS start_station_id,

        CASE 
            -- 2025 CORRECTED: start_station_longitude = start station name
            WHEN FILENAME LIKE '2025%' THEN
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:start_station_longitude::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col5::STRING), '')
                )
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:start_station_name::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col5::STRING), '')
                )
        END AS start_station_name,

        -- 📍 COORDINATES - CORRECTED MAPPING
        CASE 
            -- 2024 CORRECTED: end_station_name = start_latitude
            WHEN FILENAME LIKE '2024%' THEN
                TRY_TO_DOUBLE(RAW_DATA:end_station_name::STRING)
            -- 2025 CORRECTED: end_station_name = start_latitude
            WHEN FILENAME LIKE '2025%' THEN
                TRY_TO_DOUBLE(RAW_DATA:end_station_name::STRING)
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:start_lat::STRING),              -- 2024+ clean
                    TRY_TO_DOUBLE(RAW_DATA:start_station_latitude::STRING), -- 2013-2015
                    TRY_TO_DOUBLE(RAW_DATA:start_latitude::STRING),         -- alternate
                    TRY_TO_DOUBLE(RAW_DATA:col6::STRING)                    -- fallback
                )
        END AS start_latitude,

        CASE 
            -- 2024 CORRECTED: bikeid = start_longitude
            WHEN FILENAME LIKE '2024%' THEN
                TRY_TO_DOUBLE(RAW_DATA:bikeid::STRING)
            -- 2025 CORRECTED: bikeid = start_longitude
            WHEN FILENAME LIKE '2025%' THEN
                TRY_TO_DOUBLE(RAW_DATA:bikeid::STRING)
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:start_lng::STRING),              -- 2024+ clean
                    TRY_TO_DOUBLE(RAW_DATA:start_station_longitude::STRING),-- 2013-2015
                    TRY_TO_DOUBLE(RAW_DATA:start_longitude::STRING),        -- alternate
                    TRY_TO_DOUBLE(RAW_DATA:col7::STRING)                    -- fallback
                )
        END AS start_longitude,

        -- 🏁 END STATION - UNIVERSAL
        CASE 
            -- 2025 CORRECTED: end_station_longitude = end station ID
            WHEN FILENAME LIKE '2025%' THEN
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:end_station_longitude::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col8::STRING), '')
                )
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:end_station_id::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col8::STRING), '')
                )
        END AS end_station_id,

        CASE 
            -- 2024 CORRECTED: end_station_latitude = end_station_name
            WHEN FILENAME LIKE '2024%' THEN
                NULLIF(TRIM(RAW_DATA:end_station_latitude::STRING), '')
            -- 2025 CORRECTED: start_station_name = end station name
            WHEN FILENAME LIKE '2025%' THEN
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:start_station_name::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col9::STRING), '')
                )
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:end_station_name::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col9::STRING), '')
                )
        END AS end_station_name,

        CASE 
            -- 2024 CORRECTED: end_station_longitude = end_latitude
            WHEN FILENAME LIKE '2024%' THEN
                TRY_TO_DOUBLE(RAW_DATA:end_station_longitude::STRING)
            -- 2025 CORRECTED: end_station_latitude = end latitude
            WHEN FILENAME LIKE '2025%' THEN
                TRY_TO_DOUBLE(RAW_DATA:end_station_latitude::STRING)
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:end_lat::STRING),                -- 2024+ clean
                    TRY_TO_DOUBLE(RAW_DATA:end_station_latitude::STRING),   -- 2013-2015
                    TRY_TO_DOUBLE(RAW_DATA:end_latitude::STRING),           -- alternate
                    TRY_TO_DOUBLE(NULLIF(RAW_DATA:col10::STRING, ''))       -- fallback
                )
        END AS end_latitude,

        CASE 
            -- 2024: end_longitude not available in corrupted data
            WHEN FILENAME LIKE '2024%' THEN
                NULL
            -- 2025 CORRECTED: end_station_id = end longitude
            WHEN FILENAME LIKE '2025%' THEN
                TRY_TO_DOUBLE(RAW_DATA:end_station_id::STRING)
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:end_lng::STRING),                -- 2024+ clean
                    TRY_TO_DOUBLE(RAW_DATA:end_station_longitude::STRING),  -- 2013-2015
                    TRY_TO_DOUBLE(RAW_DATA:end_longitude::STRING),          -- alternate
                    TRY_TO_DOUBLE(NULLIF(RAW_DATA:col11::STRING, ''))       -- fallback
                )
        END AS end_longitude,

        -- 🚲 BIKE & USER DATA
        CASE 
            -- 2024 CORRUPTED: tripduration = bikeid
            WHEN FILENAME LIKE '2024%' THEN
                NULLIF(TRIM(RAW_DATA:tripduration::STRING), '')
            -- 2025 CORRECTED: tripduration = bikeid
            WHEN FILENAME LIKE '2025%' THEN
                NULLIF(TRIM(RAW_DATA:tripduration::STRING), '')
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:bikeid::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col12::STRING), '')
                )
        END AS bikeid,

        -- 👥 USER TYPE - FIXED MAPPING FOR ALL YEARS
        CASE 
            -- Map all variations to consistent values
            WHEN NULLIF(TRIM(RAW_DATA:usertype::STRING), '') IN ('Subscriber', 'member') THEN 'Subscriber'
            WHEN NULLIF(TRIM(RAW_DATA:usertype::STRING), '') IN ('Customer', 'casual') THEN 'Customer'
            WHEN RAW_DATA:member_casual::STRING = 'member' THEN 'Subscriber'
            WHEN RAW_DATA:member_casual::STRING = 'casual' THEN 'Customer'
            ELSE NULLIF(TRIM(RAW_DATA:col13::STRING), '')
        END AS usertype,

        -- 🔢 DEMOGRAPHICS - FIXED GENDER HANDLING
        COALESCE(
            TRY_TO_NUMBER(RAW_DATA:birth_year::STRING),
            TRY_TO_NUMBER(NULLIF(RAW_DATA:col14::STRING, ''))
        ) AS birth_year,

        -- 🚨 CRITICAL FIX: Handle NULL/empty gender consistently across all years
        CASE 
            WHEN NULLIF(TRIM(RAW_DATA:gender::STRING), '') IS NOT NULL THEN
                TRY_TO_NUMBER(RAW_DATA:gender::STRING)
            WHEN NULLIF(TRIM(RAW_DATA:col15::STRING), '') IS NOT NULL THEN
                TRY_TO_NUMBER(RAW_DATA:col15::STRING)
            ELSE 0  -- Default to 0 for NULL/empty gender
        END AS gender,

        -- 📄 METADATA
        FILENAME,
        FILE_MODIFIED_TIME,
        FILE_ROW_NUMBER,
        LOAD_ID,
        LOADED_AT

    FROM source
),

final_cleaned AS (
    SELECT
        *,
        -- ⏱️ DURATION CALCULATION
        CASE
            WHEN starttime IS NOT NULL AND stoptime IS NOT NULL AND starttime <= stoptime THEN
                TIMESTAMPDIFF('second', starttime, stoptime)
            ELSE NULL
        END AS tripduration,

        -- 🎯 DATA QUALITY SCORING
        CASE 
            WHEN starttime IS NOT NULL AND stoptime IS NOT NULL AND starttime <= stoptime THEN
                CASE 
                    WHEN start_station_id IS NOT NULL AND start_station_id != ''
                         AND end_station_id IS NOT NULL AND end_station_id != ''
                         AND start_latitude IS NOT NULL AND start_longitude IS NOT NULL
                    THEN 'High Quality'
                    WHEN start_station_name IS NOT NULL AND start_station_name != ''
                         OR end_station_name IS NOT NULL AND end_station_name != ''
                    THEN 'Medium Quality'
                    ELSE 'Low Quality'
                END
            ELSE 'Low Quality'
        END AS data_quality_tier

    FROM parsed
)

-- ✅ FINAL OUTPUT - CONSISTENT SCHEMA
SELECT
    tripduration,
    starttime,
    stoptime,
    start_station_id,
    start_station_name,
    start_latitude,
    start_longitude,
    end_station_id,
    end_station_name,
    end_latitude,
    end_longitude,
    bikeid,
    usertype,
    birth_year,
    gender,
    data_quality_tier,
    FILENAME,
    FILE_MODIFIED_TIME,
    FILE_ROW_NUMBER,
    LOAD_ID,
    LOADED_AT

FROM final_cleaned
-- 🎯 SMART FILTERING: Keep usable data
WHERE data_quality_tier IN ('High Quality', 'Medium Quality')
   OR (starttime IS NOT NULL AND stoptime IS NOT NULL)