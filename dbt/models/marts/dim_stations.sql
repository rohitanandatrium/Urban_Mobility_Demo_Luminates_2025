-- models/marts/dim_stations.sql
{{ config(materialized='table') }}

with raw_stations as (
  -- Start stations with trip-level granularity
  select
    trim(start_station_id) as station_id,
    nullif(trim(start_station_name), '') as station_name,
    try_to_double(start_latitude) as latitude,
    try_to_double(start_longitude) as longitude,
    starttime as activity_time,
    usertype,
    'start' as station_type,
    -- Unique trip identifier for accurate counting
    md5(concat(start_station_id, starttime::string, bikeid::string)) as trip_identifier
  from {{ ref('stg_citibike_trips') }}
  where start_station_id is not null 
    and start_station_id <> ''
    and start_station_name is not null
    -- CRITICAL FIX: Filter out swapped coordinates
    and try_to_double(start_latitude) between 40 and 41  -- NYC latitude range
    and try_to_double(start_longitude) between -75 and -73  -- NYC longitude range

  union all

  -- End stations with trip-level granularity
  select
    trim(end_station_id) as station_id,
    nullif(trim(end_station_name), '') as station_name,
    try_to_double(end_latitude) as latitude,
    try_to_double(end_longitude) as longitude,
    stoptime as activity_time,
    usertype,
    'end' as station_type,
    -- Unique trip identifier for accurate counting  
    md5(concat(end_station_id, stoptime::string, bikeid::string)) as trip_identifier
  from {{ ref('stg_citibike_trips') }}
  where end_station_id is not null 
    and end_station_id <> ''
    and end_station_name is not null
    -- CRITICAL FIX: Filter out swapped coordinates
    and try_to_double(end_latitude) between 40 and 41  -- NYC latitude range
    and try_to_double(end_longitude) between -75 and -73  -- NYC longitude range
),

station_activities as (
  select
    station_id,
    station_name,
    latitude,
    longitude,
    station_type,
    usertype,
    date_trunc('day', activity_time) as activity_date,
    -- Count unique trips per station (YEH HAR NAYE DATA KE SAATH BADHEGA)
    count(distinct trip_identifier) as daily_trips
  from raw_stations
  where station_id is not null
    and latitude is not null
    and longitude is not null
    and station_name is not null
    -- Additional safety check
    and latitude between 40 and 41
    and longitude between -75 and -73
  group by station_id, station_name, latitude, longitude, station_type, usertype, activity_date
),

station_aggregates as (
  select
    station_id,
    station_name,
    latitude,
    longitude,
    
    -- CORE METRICS THAT GROW WITH NEW DATA
    sum(daily_trips) as total_trip_activities,  -- YEH HAR BAAR BADHEGA
    count(distinct activity_date) as active_days_count,
    count(distinct station_type) as station_roles,
    count(distinct usertype) as user_types_served,
    
    -- Temporal patterns (DYNAMIC UPDATES)
    min(activity_date) as first_activity_date,
    max(activity_date) as last_activity_date,
    
    -- Usage patterns (GROWS WITH DATA)
    sum(case when usertype = 'Subscriber' then daily_trips else 0 end) as subscriber_activities,
    sum(case when usertype = 'Customer' then daily_trips else 0 end) as customer_activities,
    
    -- Daily performance (DYNAMIC)
    round(total_trip_activities * 1.0 / nullif(active_days_count, 0), 2) as avg_daily_activities

  from station_activities
  group by station_id, station_name, latitude, longitude
),

final_stations as (
  select
    -- Core identity
    station_id,
    station_name,
    latitude,
    longitude,
    
    -- Growing metrics (YEH BADHEGA HAR NAYE DATA KE SAATH)
    total_trip_activities,
    active_days_count,
    avg_daily_activities,
    
    -- User patterns
    subscriber_activities,
    customer_activities,
    round(100.0 * subscriber_activities / nullif(total_trip_activities, 0), 2) as pct_subscriber,
    
    -- Time analysis
    first_activity_date,
    last_activity_date,
    datediff('day', first_activity_date, last_activity_date) as operational_days,
    
    -- Dynamic classifications (AUTOMATICALLY UPDATES)
    case 
      when total_trip_activities > 10000 then 'Tier 1: Super Station'
      when total_trip_activities > 5000 then 'Tier 2: High Traffic'
      when total_trip_activities > 2000 then 'Tier 3: Medium Traffic' 
      when total_trip_activities > 1000 then 'Tier 4: Low Traffic'
      else 'Tier 5: Niche Station'
    end as performance_tier,
    
    case 
      when last_activity_date >= current_date() - 7 then 'Active This Week'
      when last_activity_date >= current_date() - 30 then 'Active This Month'
      else 'Dormant Station'
    end as activity_recency,
    
    -- Operational intelligence
    case 
      when operational_days < 7 then 'NEW STATION'
      when activity_recency = 'Dormant Station' then 'REQUIRES ATTENTION'
      when avg_daily_activities > 50 then 'HIGH PERFORMANCE'
      else 'STABLE OPERATION'
    end as operational_status

  from station_aggregates
  -- Final validation check
  where latitude between 40 and 41
    and longitude between -75 and -73
)

select * from final_stations
order by total_trip_activities desc