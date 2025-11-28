-- models/marts/gold/v_bike_utilization.sql
{{ config(materialized = 'view', tags = ['gold', 'kpi', 'v_bike_utilization']) }}

with trips as (
    select
        bikeid,
        starttime,
        stoptime,
        usertype,
        start_station_id,
        end_station_id
    from {{ ref('fct_trips') }}
    where bikeid is not null
      and starttime is not null
      and stoptime is not null
),

daily as (
    select
        bikeid,
        date_trunc('day', starttime) as trip_date,
        count(*) as trips_per_day,
        sum(datediff('second', starttime, stoptime)) / 3600.0 as total_hours_per_day,
        -- User patterns (DYNAMIC)
        count(case when usertype = 'Subscriber' then 1 end) as subscriber_trips,
        count(case when usertype = 'Customer' then 1 end) as customer_trips,
        -- Geographic coverage (DYNAMIC)
        count(distinct start_station_id) as unique_start_stations,
        count(distinct end_station_id) as unique_end_stations
    from trips
    group by bikeid, date_trunc('day', starttime)
),

bike_intelligence as (
    select
        bikeid,
        -- Lifetime metrics (GROWS with data)
        sum(trips_per_day) as total_trips,
        round(sum(total_hours_per_day), 2) as total_hours_in_use,
        round(avg(trips_per_day), 2) as avg_trips_per_day,
        
        -- Usage patterns (DYNAMIC)
        round(100.0 * sum(subscriber_trips) / sum(trips_per_day), 2) as overall_pct_subscriber,
        
        -- Geographic reach (GROWS with data)
        max(unique_start_stations) as max_daily_stations_used,
        round(avg(unique_start_stations), 2) as avg_daily_stations_used,
        
        -- Performance tiers (DYNAMIC - updates with new data)
        case 
            when sum(trips_per_day) > 2000 then 'High Performance'
            when sum(trips_per_day) between 1000 and 2000 then 'Medium Performance' 
            when sum(trips_per_day) between 500 and 999 then 'Low Performance'
            else 'Underutilized'
        end as performance_tier,
        
        -- Activity recency (DYNAMIC - changes daily)
        max(trip_date) as last_activity_date,
        count(distinct trip_date) as active_days,
        round(sum(trips_per_day) * 1.0 / count(distinct trip_date), 2) as trips_per_active_day

    from daily
    group by bikeid
)

select
  bikeid,
  total_trips,
  total_hours_in_use,
  avg_trips_per_day,
  performance_tier,
  active_days,
  trips_per_active_day,
  overall_pct_subscriber,
  max_daily_stations_used,
  avg_daily_stations_used,
  last_activity_date,
  
  -- Maintenance indicators (DYNAMIC)
  case 
    when last_activity_date < current_date() - 30 then 'Inactive > 30 days'
    when avg_trips_per_day < 1 then 'Low Daily Usage'
    when performance_tier = 'Underutilized' then 'Review Needed'
    else 'Normal Operation'
  end as maintenance_flag

from bike_intelligence
order by total_trips desc