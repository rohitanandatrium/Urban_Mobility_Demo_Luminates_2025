-- DIM_STATIONS
-- Unique list of bike stations derived from both start and end station columns in stg_citibike_trips
-- Produces: station_id, station_name, latitude, longitude, observations
{{ config(
    materialized='table'
) }}

with raw_stations as (

  -- start stations
  select
    trim(start_station_id)            as station_id,
    nullif(trim(start_station_name), '') as station_name,
    start_latitude                    as latitude,
    start_longitude                   as longitude,
    1                                 as occurrence
  from {{ ref('stg_citibike_trips') }}

  union all

  -- end stations
  select
    trim(end_station_id)              as station_id,
    nullif(trim(end_station_name), '')   as station_name,
    end_latitude                      as latitude,
    end_longitude                     as longitude,
    1                                 as occurrence
  from {{ ref('stg_citibike_trips') }}

),

-- Remove obviously invalid station_ids and normalize numeric columns where possible
clean_stations as (
  select
    station_id,
    station_name,
    try_to_double(latitude) as latitude,
    try_to_double(longitude) as longitude,
    occurrence
  from raw_stations
  where station_id is not null
    and station_id <> ''
),


-- Aggregate to one row per station_id.
-- Choose "max" of station_name/lat/long which effectively selects a non-null value if one exists.
agg_stations as (
  select
    station_id,
    max(station_name)    as station_name,
    max(cast(latitude as double))  as latitude,
    max(cast(longitude as double)) as longitude,
    sum(occurrence)      as observations
  from clean_stations
  group by station_id
)

select
  station_id,
  station_name,
  latitude,
  longitude,
  observations
from agg_stations
order by station_id
