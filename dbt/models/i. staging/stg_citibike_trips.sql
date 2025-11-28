{{ config(
    materialized = 'view'
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
        -- Safely parse JSON fields
        TRY_TO_NUMBER(TO_VARCHAR(RAW_DATA:col1))   AS tripduration,
        RAW_DATA:col2::TIMESTAMP_NTZ               AS starttime,
        RAW_DATA:col3::TIMESTAMP_NTZ               AS stoptime,
        RAW_DATA:col4::STRING                       AS start_station_id,
        RAW_DATA:col5::STRING                       AS start_station_name,
        RAW_DATA:col6::FLOAT                        AS start_latitude,
        RAW_DATA:col7::FLOAT                        AS start_longitude,
        RAW_DATA:col8::STRING                       AS end_station_id,
        RAW_DATA:col9::STRING                       AS end_station_name,
        RAW_DATA:col10::FLOAT                       AS end_latitude,
        RAW_DATA:col11::FLOAT                       AS end_longitude,
        RAW_DATA:col12::STRING                      AS bikeid,
        RAW_DATA:col13::STRING                      AS usertype,
        TRY_TO_NUMBER(TO_VARCHAR(RAW_DATA:col14))   AS birth_year,
        TRY_TO_NUMBER(TO_VARCHAR(RAW_DATA:col15))   AS gender,

        -- Metadata
        FILENAME,
        FILE_MODIFIED_TIME,
        FILE_ROW_NUMBER,
        LOAD_ID,
        LOADED_AT
    FROM source
)

SELECT * FROM parsed
