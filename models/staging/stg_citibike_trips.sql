{{ config(
    materialized = 'view'
) }}

WITH source AS (
    SELECT
        raw_data,
        filename,
        file_row_number,
        file_modified_time,
        load_id,
        loaded_at
    FROM {{ source('bronze', 'BRONZE_CITIBIKE_TRIPS_RAW') }}
),

parsed AS (
    SELECT
        -- Map JSON keys to structured columns
        raw_data:col1::NUMBER           AS tripduration,
        raw_data:col2::TIMESTAMP_NTZ    AS starttime,
        raw_data:col3::TIMESTAMP_NTZ    AS stoptime,
        raw_data:col4::STRING           AS start_station_id,
        raw_data:col5::STRING           AS start_station_name,
        raw_data:col6::FLOAT            AS start_latitude,
        raw_data:col7::FLOAT            AS start_longitude,
        raw_data:col8::STRING           AS end_station_id,
        raw_data:col9::STRING           AS end_station_name,
        raw_data:col10::FLOAT           AS end_latitude,
        raw_data:col11::FLOAT           AS end_longitude,
        raw_data:col12::STRING          AS bikeid,
        raw_data:col13::STRING          AS usertype,
        raw_data:col14::NUMBER          AS birth_year,
        raw_data:col15::NUMBER          AS gender,

        -- Metadata
        filename,
        file_modified_time,
        file_row_number,
        load_id,
        loaded_at
    FROM source
)

SELECT * FROM parsed
