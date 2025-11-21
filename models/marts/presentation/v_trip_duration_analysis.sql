-- models/marts/gold/v_trip_duration_analysis.sql
-- Gold view: Trip Duration Analysis
{{ config(
    materialized='view',
    tags=['gold','kpi','trip_duration_analysis']
) }}

with trips as (
  select
    duration_seconds,
    age
  from {{ ref('fct_trips') }}
  where duration_seconds is not null
),

-- bucket durations into ranges (seconds → minutes)
bucketed as (
  select
    case
      when duration_seconds < 900 then '<15 min'
      when duration_seconds between 900 and 1800 then '15–30 min'
      when duration_seconds between 1801 and 3600 then '30–60 min'
      else '>60 min'
    end as duration_bucket,
    duration_seconds,
    age
  from trips
),

agg as (
  select
    duration_bucket,
    count(*) as trip_count,
    round(avg(age),2) as avg_rider_age
  from bucketed
  group by duration_bucket
)

select
  duration_bucket,
  trip_count,
  avg_rider_age
from agg
order by
  case duration_bucket
    when '<15 min' then 1
    when '15–30 min' then 2
    when '30–60 min' then 3
    else 4
  end
