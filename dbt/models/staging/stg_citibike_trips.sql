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
),

parsed AS (
    SELECT
        -- TIMESTAMP MAPPING CORRECTED FOR 2024 DATA
        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024 FIX: stoptime contains ACTUAL starttime (based on your data sample)
                TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING)
            ELSE
                -- EXISTING MAPPING FOR OLD DATA
                COALESCE(
                    TRY_TO_TIMESTAMP(RAW_DATA:started_at::STRING),
                    TRY_TO_TIMESTAMP(RAW_DATA:starttime::STRING),
                    TRY_TO_TIMESTAMP(RAW_DATA:col2::STRING)
                )
        END AS starttime,

        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024 FIX: start_station_id contains ACTUAL stoptime (based on your data sample)  
                TRY_TO_TIMESTAMP(RAW_DATA:start_station_id::STRING)
            ELSE
                COALESCE(
                    TRY_TO_TIMESTAMP(RAW_DATA:ended_at::STRING),
                    TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING),
                    TRY_TO_TIMESTAMP(RAW_DATA:col3::STRING)
                )
        END AS stoptime,

        -- STATION MAPPING (correct based on your data)
        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: start_station_latitude contains station ID
                NULLIF(TRIM(RAW_DATA:start_station_latitude::STRING), '')
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:start_station_id::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col4::STRING), '')
                )
        END AS start_station_id,

        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: start_station_name is correct
                NULLIF(TRIM(RAW_DATA:start_station_name::STRING), '')
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:start_station_name::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col5::STRING), '')
                )
        END AS start_station_name,

        -- COORDINATES MAPPING
        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: end_station_name contains start_latitude
                TRY_TO_DOUBLE(RAW_DATA:end_station_name::STRING)
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:start_station_latitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:start_latitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:start_lat::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:col6::STRING)
                )
        END AS start_latitude,

        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: bikeid contains start_longitude
                TRY_TO_DOUBLE(RAW_DATA:bikeid::STRING)
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:start_station_longitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:start_longitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:start_lng::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:col7::STRING)
                )
        END AS start_longitude,

        -- END STATION MAPPING
        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: end_station_id is correct
                NULLIF(TRIM(RAW_DATA:end_station_id::STRING), '')
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:end_station_id::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col8::STRING), '')
                )
        END AS end_station_id,

        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: end_station_latitude contains end_station_name
                NULLIF(TRIM(RAW_DATA:end_station_latitude::STRING), '')
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:end_station_name::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col9::STRING), '')
                )
        END AS end_station_name,

        -- END COORDINATES
        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: end_station_longitude contains end_latitude
                TRY_TO_DOUBLE(RAW_DATA:end_station_longitude::STRING)
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:end_station_latitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:end_latitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:end_lat::STRING),
                    TRY_TO_DOUBLE(NULLIF(RAW_DATA:col10::STRING, ''))
                )
        END AS end_latitude,

        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: end_lng not available
                NULL
            ELSE
                COALESCE(
                    TRY_TO_DOUBLE(RAW_DATA:end_station_longitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:end_longitude::STRING),
                    TRY_TO_DOUBLE(RAW_DATA:end_lng::STRING),
                    TRY_TO_DOUBLE(NULLIF(RAW_DATA:col11::STRING, ''))
                )
        END AS end_longitude,

        -- BIKE & USER DATA
        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: tripduration contains bikeid
                NULLIF(TRIM(RAW_DATA:tripduration::STRING), '')
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:bikeid::STRING), ''),
                    NULLIF(TRIM(RAW_DATA:col12::STRING), '')
                )
        END AS bikeid,

        CASE 
            WHEN FILENAME LIKE '202402%' THEN
                -- 2024: usertype is correct
                NULLIF(TRIM(RAW_DATA:usertype::STRING), '')
            ELSE
                COALESCE(
                    NULLIF(TRIM(RAW_DATA:usertype::STRING), ''),
                    CASE 
                        WHEN RAW_DATA:member_casual::STRING = 'member' THEN 'Subscriber'
                        WHEN RAW_DATA:member_casual::STRING = 'casual' THEN 'Customer'
                        ELSE NULL
                    END,
                    NULLIF(TRIM(RAW_DATA:col13::STRING), '')
                )
        END AS usertype,

        -- DEMOGRAPHICS
        CASE 
            WHEN RAW_DATA:birth_year::STRING IS NOT NULL AND RAW_DATA:birth_year::STRING != '' THEN
                TRY_TO_NUMBER(RAW_DATA:birth_year::STRING)
            WHEN RAW_DATA:col14::STRING IS NOT NULL AND RAW_DATA:col14::STRING != '' THEN
                TRY_TO_NUMBER(RAW_DATA:col14::STRING)
            ELSE NULL
        END AS birth_year,

        CASE 
            WHEN RAW_DATA:gender::STRING IS NOT NULL AND RAW_DATA:gender::STRING != '' THEN
                TRY_TO_NUMBER(RAW_DATA:gender::STRING)
            WHEN RAW_DATA:col15::STRING IS NOT NULL AND RAW_DATA:col15::STRING != '' THEN
                TRY_TO_NUMBER(RAW_DATA:col15::STRING)
            ELSE NULL
        END AS gender,

        -- METADATA
        FILENAME,
        FILE_MODIFIED_TIME,
        FILE_ROW_NUMBER,
        LOAD_ID,
        LOADED_AT

    FROM source
    WHERE RAW_DATA IS NOT NULL
),

final_cleaned AS (
    SELECT
        *,
        -- Calculate duration from CORRECTED timestamps
        CASE
            WHEN starttime IS NOT NULL AND stoptime IS NOT NULL AND starttime <= stoptime THEN
                TIMESTAMPDIFF('second', starttime, stoptime)
            ELSE NULL
        END AS tripduration,

        -- Data quality with timestamp validation
        CASE 
            WHEN starttime IS NOT NULL AND stoptime IS NOT NULL AND starttime <= stoptime THEN
                CASE 
                    WHEN start_station_id IS NOT NULL AND start_station_id != ''
                         AND end_station_id IS NOT NULL AND end_station_id != ''
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
WHERE data_quality_tier IN ('High Quality', 'Medium Quality')
   OR (starttime IS NOT NULL AND stoptime IS NOT NULL AND starttime <= stoptime)