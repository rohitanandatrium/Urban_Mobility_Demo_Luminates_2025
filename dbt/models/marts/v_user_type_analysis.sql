-- models/marts/gold/v_user_type_analysis.sql
-- Gold view: user type level trip analysis by time of day
{{ config(
    materialized='view',
    tags=['gold','kpi','user_type_analysis']
) }}

with trips as (
  select
    usertype,
    duration_seconds,
    starttime
  from {{ ref('fct_trips') }}
  where usertype is not null
),

-- derive time of day bucket
time_buckets as (
  select
    usertype,
    duration_seconds,
    case
      when extract(hour from starttime) between 5 and 11 then 'Morning'
      when extract(hour from starttime) between 12 and 16 then 'Afternoon'
      when extract(hour from starttime) between 17 and 20 then 'Evening'
      else 'Night'
    end as time_of_day
  from trips
),

-- aggregate by user type and time of day
agg as (
  select
    usertype,
    time_of_day,
    count(*) as total_trips,
    round(avg(duration_seconds),2) as avg_trip_duration_sec
  from time_buckets
  group by 1,2
),

-- totals per user type
user_totals as (
  select
    usertype,
    sum(total_trips) as total_trips,
    round(avg(avg_trip_duration_sec),2) as avg_trip_duration_sec
  from agg
  group by 1
)

select
  ut.usertype,
  ut.total_trips,
  ut.avg_trip_duration_sec,
  a.time_of_day,
  a.total_trips as trips_by_time_of_day
from user_totals ut
left join agg a
  on ut.usertype = a.usertype
order by ut.usertype, a.time_of_day
