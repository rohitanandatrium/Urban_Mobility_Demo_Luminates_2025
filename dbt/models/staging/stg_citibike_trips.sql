{{ config(
    materialized = 'table'
) }}

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
        -- Use ACTUAL JSON field names from your Bronze table
        TRY_TO_NUMBER(RAW_DATA:tripduration::STRING)   AS tripduration,
        -- Handle ALL timestamp formats - try multiple approaches
        CASE 
            WHEN RAW_DATA:starttime::STRING IS NOT NULL AND RAW_DATA:starttime::STRING != '' THEN
                COALESCE(
                    TRY_TO_TIMESTAMP(RAW_DATA:starttime::STRING, 'MM/DD/YYYY HH24:MI'),
                    TRY_TO_TIMESTAMP(RAW_DATA:starttime::STRING, 'MM/DD/YYYY HH12:MI'),
                    TRY_TO_TIMESTAMP(RAW_DATA:starttime::STRING)
                )
            ELSE NULL
        END AS starttime,
        
        CASE 
            WHEN RAW_DATA:stoptime::STRING IS NOT NULL AND RAW_DATA:stoptime::STRING != '' THEN
                COALESCE(
                    TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING, 'MM/DD/YYYY HH24:MI'),
                    TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING, 'MM/DD/YYYY HH12:MI'),
                    TRY_TO_TIMESTAMP(RAW_DATA:stoptime::STRING)
                )
            ELSE NULL
        END AS stoptime,
        
        RAW_DATA:start_station_id::STRING             AS start_station_id,
        RAW_DATA:start_station_name::STRING           AS start_station_name,
        TRY_TO_DOUBLE(RAW_DATA:start_station_latitude::STRING)  AS start_latitude,
        TRY_TO_DOUBLE(RAW_DATA:start_station_longitude::STRING) AS start_longitude,
        RAW_DATA:end_station_id::STRING               AS end_station_id,
        RAW_DATA:end_station_name::STRING             AS end_station_name,
        TRY_TO_DOUBLE(RAW_DATA:end_station_latitude::STRING)    AS end_latitude,
        TRY_TO_DOUBLE(RAW_DATA:end_station_longitude::STRING)   AS end_longitude,
        RAW_DATA:bikeid::STRING                       AS bikeid,
        RAW_DATA:usertype::STRING                     AS usertype,
        TRY_TO_NUMBER(NULLIF(RAW_DATA:birth_year::STRING, '')) AS birth_year,
        TRY_TO_NUMBER(RAW_DATA:gender::STRING)        AS gender,

        -- Metadata
        FILENAME,
        FILE_MODIFIED_TIME,
        FILE_ROW_NUMBER,
        LOAD_ID,
        LOADED_AT
    FROM source
)

SELECT * FROM parsed