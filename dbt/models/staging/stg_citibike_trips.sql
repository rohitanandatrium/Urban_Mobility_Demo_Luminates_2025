{{
    config(
        materialized = 'table'
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
            WHEN FILENAME LIKE '202402%' THEN
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
            WHEN FILENAME LIKE '202402%' THEN
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
            WHEN FILENAME LIKE '202402%' THEN
                NULLIF(TRIM(RAW_DATA:start_station_latitude::STRING), '')
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:start_station_id::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col4::STRING), '')
                )
        END AS start_station_id,

        COALESCE(
            NULLIF(TRIM(RAW_DATA:start_station_name::STRING), ''),
            NULLIF(TRIM(RAW_DATA:col5::STRING), '')
        ) AS start_station_name,

        -- 📍 COORDINATES - ALL FORMATS
        COALESCE(
            TRY_TO_DOUBLE(RAW_DATA:start_lat::STRING),              -- 2024+ clean
            TRY_TO_DOUBLE(RAW_DATA:start_station_latitude::STRING), -- 2013-2015
            TRY_TO_DOUBLE(RAW_DATA:start_latitude::STRING),         -- alternate
            TRY_TO_DOUBLE(RAW_DATA:col6::STRING)                    -- fallback
        ) AS start_latitude,

        COALESCE(
            TRY_TO_DOUBLE(RAW_DATA:start_lng::STRING),              -- 2024+ clean
            TRY_TO_DOUBLE(RAW_DATA:start_station_longitude::STRING),-- 2013-2015
            TRY_TO_DOUBLE(RAW_DATA:start_longitude::STRING),        -- alternate
            TRY_TO_DOUBLE(RAW_DATA:col7::STRING)                    -- fallback
        ) AS start_longitude,

        -- 🏁 END STATION - UNIVERSAL
        COALESCE(
            NULLIF(TRIM(RAW_DATA:end_station_id::STRING), ''),
            NULLIF(TRIM(RAW_DATA:col8::STRING), '')
        ) AS end_station_id,

        COALESCE(
            NULLIF(TRIM(RAW_DATA:end_station_name::STRING), ''),
            NULLIF(TRIM(RAW_DATA:col9::STRING), '')
        ) AS end_station_name,

        COALESCE(
            TRY_TO_DOUBLE(RAW_DATA:end_lat::STRING),                -- 2024+ clean
            TRY_TO_DOUBLE(RAW_DATA:end_station_latitude::STRING),   -- 2013-2015
            TRY_TO_DOUBLE(RAW_DATA:end_latitude::STRING),           -- alternate
            TRY_TO_DOUBLE(NULLIF(RAW_DATA:col10::STRING, ''))       -- fallback
        ) AS end_latitude,

        COALESCE(
            TRY_TO_DOUBLE(RAW_DATA:end_lng::STRING),                -- 2024+ clean
            TRY_TO_DOUBLE(RAW_DATA:end_station_longitude::STRING),  -- 2013-2015
            TRY_TO_DOUBLE(RAW_DATA:end_longitude::STRING),          -- alternate
            TRY_TO_DOUBLE(NULLIF(RAW_DATA:col11::STRING, ''))       -- fallback
        ) AS end_longitude,

        -- 🚲 BIKE & USER DATA
        CASE 
            -- 2024 CORRUPTED: tripduration = bikeid
            WHEN FILENAME LIKE '202402%' THEN
                NULLIF(TRIM(RAW_DATA:tripduration::STRING), '')
            -- ALL OTHER YEARS
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:bikeid::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col12::STRING), '')
                )
        END AS bikeid,

        -- 👥 USER TYPE - SMART MAPPING
        COALESCE(
            NULLIF(TRIM(RAW_DATA:usertype::STRING), ''),
            CASE 
                WHEN RAW_DATA:member_casual::STRING = 'member' THEN 'Subscriber'
                WHEN RAW_DATA:member_casual::STRING = 'casual' THEN 'Customer'
                ELSE NULL
            END,
            NULLIF(TRIM(RAW_DATA:col13::STRING), '')
        ) AS usertype,

        -- 🔢 DEMOGRAPHICS
        COALESCE(
            TRY_TO_NUMBER(RAW_DATA:birth_year::STRING),
            TRY_TO_NUMBER(NULLIF(RAW_DATA:col14::STRING, ''))
        ) AS birth_year,

        COALESCE(
            TRY_TO_NUMBER(RAW_DATA:gender::STRING),
            TRY_TO_NUMBER(NULLIF(RAW_DATA:col15::STRING, ''))
        ) AS gender,

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