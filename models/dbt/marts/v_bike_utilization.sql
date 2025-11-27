-- models/marts/gold/v_bike_utilization.sql
-- ==========================================================
-- Gold View: Bike-Level Utilization Metrics
-- KPIs: Total Trips, Total Hours in Use, Average Trips per Day
-- Business Value: Monitors fleet utilization to identify underused or faulty bikes
-- ==========================================================

{{ config(
    materialized = 'view',
    tags = ['gold', 'kpi', 'bike_utilization']
) }}

with
-- =====================
-- BASE TRIP DATA
-- =====================
trips as (
    select
        bikeid,
        starttime,
        stoptime,
        datediff('second', starttime, stoptime) as duration_seconds
    from {{ ref('fct_trips') }}
    where bikeid is not null
      and starttime is not null
      and stoptime is not null
),

-- =====================
-- DAILY UTILIZATION SUMMARY
-- =====================
daily as (
    select
        bikeid,
        date_trunc('day', starttime) as trip_date,
        count(*) as trips_per_day,
        sum(duration_seconds) / 3600.0 as total_hours_per_day
    from trips
    group by
        bikeid,
        date_trunc('day', starttime)
),

-- =====================
-- BIKE-LEVEL AGGREGATION
-- =====================
agg as (
    select
        bikeid,
        sum(trips_per_day) as total_trips,
        round(sum(total_hours_per_day), 2) as total_hours_in_use,
        round(avg(trips_per_day), 2) as avg_trips_per_day
    from daily
    group by bikeid
)

-- =====================
-- FINAL OUTPUT
-- =====================
select
    bikeid,
    total_trips,
    total_hours_in_use,
    avg_trips_per_day
from agg
order by total_trips desc
