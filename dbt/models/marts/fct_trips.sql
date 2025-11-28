-- models/marts/fct_trips.sql
-- ==========================================================
-- Advanced Fact Table: Trip Intelligence Platform
-- Features: Multi-dimensional analytics, data quality scoring, growth tracking
-- Business Value: Complete trip intelligence for operational and strategic analytics
-- ==========================================================

{{ config(
    materialized='table'
) }}

with
-- =====================
-- ENHANCED SOURCE DATA PLATFORM
-- =====================
source as (
  select
    -- Core trip metrics
    tripduration,
    starttime,
    stoptime,
    start_station_id,
    end_station_id,
    bikeid,
    usertype,
    birth_year,
    gender,
    
    -- Geographic context
    start_latitude,
    start_longitude, 
    end_latitude,
    end_longitude,
    
    -- Metadata for data lineage
    file_row_number,
    filename,
    file_modified_time,
    load_id,
    loaded_at
  from {{ ref('stg_citibike_trips') }}
),

-- =====================
-- ADVANCED TRIP INTELLIGENCE ENGINE
-- =====================
trip_intelligence as (
  select
    -- Enhanced Unique Trip Identifier
    md5(
      concat_ws('|',
        coalesce(cast(starttime as string), ''),
        coalesce(cast(stoptime as string), ''),
        coalesce(cast(bikeid as string), ''),
        coalesce(cast(start_station_id as string), ''),
        coalesce(cast(end_station_id as string), ''),
        coalesce(cast(file_row_number as string), '')
      )
    ) as trip_id,

    -- Core temporal dimensions
    starttime,
    stoptime,

    -- Smart Duration Calculation with Quality Scoring
    case
      when tripduration is not null then tripduration
      when starttime is not null and stoptime is not null then
        timestampdiff(second, starttime, stoptime)
      else null
    end as duration_seconds,

    -- Duration Quality Indicator
    case
      when tripduration is not null then 'Provided Duration'
      when starttime is not null and stoptime is not null then 'Calculated Duration'
      else 'Missing Duration'
    end as duration_source,

    -- Station Intelligence
    start_station_id,
    end_station_id,
    
    -- Geographic Intelligence
    start_latitude,
    start_longitude,
    end_latitude,
    end_longitude,
    
    -- Approximate Distance (simplified haversine)
    case
      when start_latitude is not null and start_longitude is not null 
           and end_latitude is not null and end_longitude is not null
      then sqrt(
        power((end_latitude - start_latitude) * 111.32, 2) +  -- 1 degree lat ≈ 111.32 km
        power((end_longitude - start_longitude) * 85.0, 2)     -- 1 degree long ≈ 85.0 km at NYC lat
      )
      else null
    end as approx_distance_km,

    -- User Intelligence Platform
    bikeid,
    usertype,
    birth_year,
    gender,

    -- Advanced Temporal Enrichments
    extract(year from starttime) as trip_year,
    extract(month from starttime) as trip_month,
    extract(day from starttime) as trip_day,
    extract(hour from starttime) as hour_of_day,
    extract(minute from starttime) as minute_of_hour,
    
    -- Enhanced Day Analysis
    extract(dow from starttime) + 1 as day_of_week,  -- 1=Sunday
    case
      when extract(dow from starttime) in (0,6) then true  -- Sun=0, Sat=6
      else false
    end as is_weekend,
    
    -- Peak Period Intelligence
    case
      when extract(hour from starttime) between 7 and 9 then 'Morning Peak (7-9 AM)'
      when extract(hour from starttime) between 17 and 19 then 'Evening Peak (5-7 PM)'
      when extract(hour from starttime) between 12 and 14 then 'Lunch Peak (12-2 PM)'
      else 'Off-Peak'
    end as peak_period,
    
    -- Seasonal Intelligence
    case 
      when extract(month from starttime) in (12,1,2) then 'Winter'
      when extract(month from starttime) in (3,4,5) then 'Spring' 
      when extract(month from starttime) in (6,7,8) then 'Summer'
      else 'Fall'
    end as season,

    -- Advanced User Demographics
    case
      when birth_year is null or birth_year = 0 then null
      else extract(year from current_date()) - birth_year
    end as age,
    
    -- Age Group Classification
    case
      when birth_year is null or birth_year = 0 then 'Unknown'
      when extract(year from current_date()) - birth_year < 18 then 'Under 18'
      when extract(year from current_date()) - birth_year between 18 and 25 then '18-25'
      when extract(year from current_date()) - birth_year between 26 and 35 then '26-35'
      when extract(year from current_date()) - birth_year between 36 and 50 then '36-50'
      when extract(year from current_date()) - birth_year between 51 and 65 then '51-65'
      else '65+'
    end as age_group,

    -- Enhanced Gender Classification
    case
      when gender = 1 then 'Male'
      when gender = 2 then 'Female'
      when gender = 0 then 'Unknown'
      else 'Not Specified'
    end as gender_category,

    -- Trip Efficiency Scoring
    case
      when duration_seconds is not null and approx_distance_km is not null
      then round(duration_seconds / 60.0 / nullif(approx_distance_km, 0), 2)  -- minutes per km
      else null
    end as minutes_per_km,

    -- Data Quality Scoring
    case
      when starttime is not null and stoptime is not null 
           and start_station_id is not null and end_station_id is not null
           and bikeid is not null and usertype is not null
      then 'High Quality'
      when starttime is not null and stoptime is not null 
           and (start_station_id is not null or end_station_id is not null)
      then 'Medium Quality' 
      else 'Low Quality'
    end as data_quality_tier,

    -- Business Rule Validations
    case 
      when start_station_id = end_station_id then 'Round Trip'
      else 'Point-to-Point'
    end as trip_type,
    
    case
      when duration_seconds < 60 then 'Suspiciously Short (<1 min)'
      when duration_seconds > 86400 then 'Suspiciously Long (>24 hours)'
      else 'Normal Duration'
    end as duration_validation,

    -- Growth Tracking Metadata
    filename,
    file_modified_time,
    file_row_number,
    load_id,
    loaded_at,

    -- Data Freshness Indicator
    case
      when starttime >= current_date() - 7 then 'Recent (Last 7 Days)'
      when starttime >= current_date() - 30 then 'Current (Last 30 Days)'
      when starttime >= current_date() - 90 then 'Recent Historical (Last 90 Days)'
      else 'Historical'
    end as data_freshness

  from source
),

-- =====================
-- PERFORMANCE OPTIMIZATION LAYER
-- =====================
performance_optimized as (
  select
    *,
    
    -- Popular Route Identification
    case
      when trip_type = 'Point-to-Point' then md5(concat_ws('|', start_station_id, end_station_id))
      else null
    end as route_id,
    
    -- Time-based Partitioning Keys
    date_trunc('month', starttime) as month_partition_key,
    date_trunc('week', starttime) as week_partition_key,
    
    -- Performance Tier Classification
    case
      when duration_seconds between 300 and 1800 and peak_period != 'Off-Peak' then 'Prime Commute'
      when duration_seconds > 1800 and is_weekend = true then 'Weekend Leisure'
      when duration_seconds < 300 then 'Quick Ride'
      else 'Standard Trip'
    end as trip_profile,

    -- Operational Intelligence
    case
      when peak_period != 'Off-Peak' and data_quality_tier = 'High Quality' then 'High Value Record'
      when data_quality_tier = 'High Quality' then 'Quality Record'
      else 'Standard Record'
    end as analytical_value

  from trip_intelligence
)

-- =====================
-- FINAL INTELLIGENCE OUTPUT
-- =====================
select
  -- Core Identifiers
  trip_id,
  route_id,
  
  -- Temporal Dimensions
  starttime,
  stoptime,
  trip_year,
  trip_month, 
  trip_day,
  hour_of_day,
  minute_of_hour,
  day_of_week,
  is_weekend,
  peak_period,
  season,
  month_partition_key,
  week_partition_key,
  
  -- Core Trip Metrics
  duration_seconds,
  duration_source,
  approx_distance_km,
  minutes_per_km,
  
  -- Station Intelligence
  start_station_id,
  end_station_id,
  start_latitude,
  start_longitude,
  end_latitude, 
  end_longitude,
  
  -- User Intelligence
  bikeid,
  usertype,
  birth_year,
  gender,
  gender_category,
  age,
  age_group,
  
  -- Advanced Analytics
  trip_type,
  trip_profile,
  data_quality_tier,
  duration_validation,
  analytical_value,
  data_freshness,
  
  -- Data Lineage
  filename,
  file_modified_time,
  file_row_number,
  load_id,
  loaded_at

from performance_optimized
-- Strategic partitioning for performance
where starttime is not null
  and duration_seconds is not null
  and data_quality_tier != 'Low Quality'
order by 
  starttime desc,
  data_quality_tier desc,
  analytical_value desc