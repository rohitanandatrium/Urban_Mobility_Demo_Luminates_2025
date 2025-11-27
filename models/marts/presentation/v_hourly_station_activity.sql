-- models/marts/gold/v_hourly_station_activity.sql
-- ==========================================================
-- Gold View: Hourly Station Activity
-- KPIs: Departures per Hour, Arrivals per Hour, Net Flow (Departures - Arrivals)
-- Business Value: Helps operations teams identify stations that are running empty or full
-- ==========================================================

{{ config(
    materialized = 'view',
    tags = ['gold', 'kpi', 'station_activity']
) }}

with
-- =====================
-- BASE TRIP DATA
-- =====================
trips as (
    select
        trip_id,
        start_station_id,
        end_station_id,
        starttime,
        stoptime
    from {{ ref('fct_trips') }}
    where starttime is not null
      and stoptime is not null
),

-- =====================
-- DEPARTURES
-- =====================
departures as (
    select
        coalesce(trim(start_station_id), '') as station_id,
        date_trunc('hour', starttime) as hour_ts,
        extract(year from starttime)  as year,
        extract(month from starttime) as month,
        extract(day from starttime)   as day,
        extract(hour from starttime)  as hour_of_day,
        count(*) as departures_count
    from trips
    where start_station_id is not null
    group by
        coalesce(trim(start_station_id), ''),
        date_trunc('hour', starttime),
        extract(year from starttime),
        extract(month from starttime),
        extract(day from starttime),
        extract(hour from starttime)
),

-- =====================
-- ARRIVALS
-- =====================
arrivals as (
    select
        coalesce(trim(end_station_id), '') as station_id,
        date_trunc('hour', stoptime) as hour_ts,
        extract(year from stoptime)  as year,
        extract(month from stoptime) as month,
        extract(day from stoptime)   as day,
        extract(hour from stoptime)  as hour_of_day,
        count(*) as arrivals_count
    from trips
    where end_station_id is not null
    group by
        coalesce(trim(end_station_id), ''),
        date_trunc('hour', stoptime),
        extract(year from stoptime),
        extract(month from stoptime),
        extract(day from stoptime),
        extract(hour from stoptime)
),

-- =====================
-- HOURLY METRICS JOIN
-- =====================
hourly_metrics as (
    select
        coalesce(d.station_id, a.station_id) as station_id,
        coalesce(d.hour_ts, a.hour_ts)       as hour_ts,
        coalesce(d.year, a.year)             as year,
        coalesce(d.month, a.month)           as month,
        coalesce(d.day, a.day)               as day,
        coalesce(d.hour_of_day, a.hour_of_day) as hour_of_day,
        coalesce(d.departures_count, 0) as departures,
        coalesce(a.arrivals_count, 0)   as arrivals,
        coalesce(d.departures_count, 0) - coalesce(a.arrivals_count, 0) as net_flow
    from departures d
    full outer join arrivals a
        on d.station_id = a.station_id
        and d.hour_ts = a.hour_ts
)

-- =====================
-- FINAL OUTPUT
-- =====================
select
    hm.station_id,
    s.station_name,
    hm.hour_ts as activity_hour_ts,
    hm.year,
    hm.month,
    hm.day,
    hm.hour_of_day,
    hm.departures,
    hm.arrivals,
    hm.net_flow
from hourly_metrics hm
left join {{ ref('dim_stations') }} s
    on s.station_id = hm.station_id
order by hm.station_id, hm.hour_ts
