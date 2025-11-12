-- models/marts/fct_trips.sql
-- FCT_TRIPS
-- Trip-level fact model for analytical reporting built on stg_citibike_trips
-- Includes trip duration, station IDs, user info, and temporal enrichments
{{ config(
    materialized='table'
) }}

with source as (

  select
    tripduration,
    starttime,
    stoptime,
    start_station_id,
    end_station_id,
    bikeid,
    usertype,
    birth_year,
    gender,
    file_row_number,
    load_id,
    loaded_at
  from {{ ref('stg_citibike_trips') }}

),

-- Derive a unique trip key and compute duration if not provided
trip_enriched as (
  select
    md5(
      concat_ws('|',
        coalesce(cast(starttime as string), ''),
        coalesce(cast(stoptime as string), ''),
        coalesce(cast(bikeid as string), ''),
        coalesce(cast(file_row_number as string), '')
      )
    ) as trip_id,

    starttime,
    stoptime,

    -- prefer provided duration; fallback to computed duration
    case
      when tripduration is not null then tripduration
      when starttime is not null and stoptime is not null then
        timestampdiff(second, starttime, stoptime)
      else null
    end as duration_seconds,

    start_station_id,
    end_station_id,
    bikeid,
    usertype,
    birth_year,
    gender,

    -- temporal enrichments
    extract(hour from starttime) as hour_of_day,
    extract(dow from starttime) + 1 as day_of_week,  -- 1=Sunday
    case
      when extract(dow from starttime) in (5,6) then true  -- Sat=5, Sun=6 (adjust for your warehouse)
      else false
    end as is_weekend,

    -- derived user age
    case
      when birth_year is null or birth_year = 0 then null
      else extract(year from current_date()) - birth_year
    end as age,

    load_id,
    loaded_at

  from source
)

select *
from trip_enriched
order by starttime