-- models/marts/gold/v_popular_routes.sql
-- Gold view: popular routes between stations with duration and usertype mix
{{ config(
    materialized='view',
    tags=['gold','kpi','popular_routes']
) }}

with trips as (
  select
    start_station_id,
    end_station_id,
    usertype,
    duration_seconds
  from {{ ref('fct_trips') }}
  where start_station_id is not null
    and end_station_id is not null
),

-- aggregate route metrics
route_summary as (
  select
    start_station_id,
    end_station_id,
    count(*)                                   as trip_count,
    avg(duration_seconds)                      as avg_duration_sec,
    sum(case when lower(usertype) = 'subscriber' then 1 else 0 end) as subscriber_trips,
    sum(case when lower(usertype) in ('customer','casual') then 1 else 0 end) as customer_trips
  from trips
  group by 1,2
),

-- percentage breakdown
route_kpis as (
  select
    start_station_id,
    end_station_id,
    trip_count,
    round(avg_duration_sec,2) as avg_duration_sec,
    subscriber_trips,
    customer_trips,
    round(100.0 * subscriber_trips / nullif(trip_count,0),2) as pct_subscriber,
    round(100.0 * customer_trips   / nullif(trip_count,0),2) as pct_customer
  from route_summary
)

select
  rk.start_station_id,
  s1.station_name as start_station_name,
  rk.end_station_id,
  s2.station_name as end_station_name,
  rk.trip_count,
  rk.avg_duration_sec,
  rk.subscriber_trips,
  rk.customer_trips,
  rk.pct_subscriber,
  rk.pct_customer
from route_kpis rk
left join {{ ref('dim_stations') }} s1 on rk.start_station_id = s1.station_id
left join {{ ref('dim_stations') }} s2 on rk.end_station_id   = s2.station_id
order by rk.trip_count desc
