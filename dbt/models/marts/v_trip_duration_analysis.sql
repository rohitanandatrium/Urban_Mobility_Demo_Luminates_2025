-- models/marts/gold/v_trip_duration_analysis.sql
{{ config(
    materialized='table',
    tags=['gold','kpi','trip_duration_analysis']
) }}

with trips as (
  select
    trip_id,
    duration_seconds,
    age,
    usertype,
    starttime,
    start_station_id,
    end_station_id,
    extract(month from starttime) as trip_month,
    extract(year from starttime) as trip_year
  from {{ ref('fct_trips') }}
  where duration_seconds is not null
    and duration_seconds between 60 and 86400
),

bucketed as (
  select
    trip_id,
    case
      when duration_seconds < 300 then '0-5 min (Quick Ride)'
      when duration_seconds < 600 then '5-10 min (Short Commute)'
      when duration_seconds < 900 then '10-15 min (Standard Trip)'
      when duration_seconds < 1200 then '15-20 min (Extended Ride)'
      when duration_seconds < 1800 then '20-30 min (Leisure)'
      when duration_seconds < 2700 then '30-45 min (Long Ride)'
      when duration_seconds < 3600 then '45-60 min (Tour)'
      when duration_seconds < 7200 then '1-2 hours (Extended Tour)'
      else '2+ hours (Premium Rental)'
    end as duration_bucket,
    
    case
      when duration_seconds < 180 then 'Micro Ride (<3min)'
      when duration_seconds between 180 and 600 then 'Short Ride (3-10min)'
      when duration_seconds between 600 and 1800 then 'Standard Ride (10-30min)'
      when duration_seconds between 1800 and 3600 then 'Long Ride (30-60min)'
      else 'Extended Ride (>60min)'
    end as duration_sub_bucket,
    
    duration_seconds,
    age,
    usertype,
    extract(hour from starttime) as hour_of_day,
    
    case 
      when extract(dow from starttime) in (0,6) then 'Weekend'
      else 'Weekday'
    end as day_type,
    
    case
      when extract(hour from starttime) between 7 and 9 then 'Morning Peak'
      when extract(hour from starttime) between 17 and 19 then 'Evening Peak'
      when extract(hour from starttime) between 12 and 14 then 'Lunch Peak'
      else 'Off-Peak'
    end as peak_period,
    
    case 
      when extract(month from starttime) in (12,1,2) then 'Winter'
      when extract(month from starttime) in (3,4,5) then 'Spring' 
      when extract(month from starttime) in (6,7,8) then 'Summer'
      else 'Fall'
    end as season,
    
    start_station_id,
    end_station_id,
    trip_month,
    trip_year
  from trips
),

agg as (
  select
    duration_bucket,
    duration_sub_bucket,
    usertype,
    day_type,
    peak_period,
    season,
    hour_of_day,
    trip_month,
    trip_year,
    
    count(trip_id) as trip_count,
    count(distinct start_station_id) as unique_start_stations,
    count(distinct end_station_id) as unique_end_stations,
    round(avg(age),2) as avg_rider_age,
    round(avg(duration_seconds)/60,2) as avg_duration_minutes,
    round(min(duration_seconds)/60,2) as min_duration_minutes,
    round(max(duration_seconds)/60,2) as max_duration_minutes,
    
    round(100.0 * count(*) / nullif(sum(count(*)) over(), 0), 3) as pct_of_total_trips,
    
    case 
      when hour_of_day between 6 and 10 then 'Morning'
      when hour_of_day between 11 and 15 then 'Afternoon'
      when hour_of_day between 16 and 20 then 'Evening'
      else 'Night'
    end as day_segment
  from bucketed
  group by 
    duration_bucket, duration_sub_bucket, usertype, day_type, 
    peak_period, season, hour_of_day, trip_month, trip_year
)

select
  duration_bucket,
  duration_sub_bucket,
  usertype,
  day_type,
  peak_period,
  season,
  hour_of_day,
  trip_month,
  trip_year,
  day_segment,
  
  trip_count,
  unique_start_stations,
  unique_end_stations,
  avg_rider_age,
  avg_duration_minutes,
  min_duration_minutes,
  max_duration_minutes,
  pct_of_total_trips,
  
  rank() over(partition by duration_bucket order by trip_count desc) as bucket_popularity_rank,
  rank() over(partition by usertype order by trip_count desc) as user_type_rank,
  rank() over(partition by season order by trip_count desc) as seasonal_rank,
  
  case 
    when trip_count > 1000 then 'High Volume'
    when trip_count > 500 then 'Medium Volume'
    when trip_count > 100 then 'Low Volume'
    else 'Niche'
  end as volume_category,
  
  case 
    when avg_duration_minutes < 10 then 'Quick Trips'
    when avg_duration_minutes between 10 and 20 then 'Standard Trips'
    when avg_duration_minutes between 20 and 40 then 'Extended Trips'
    else 'Long Duration'
  end as duration_profile,
  
  case 
    when trip_month = extract(month from current_date()) 
     and trip_year = extract(year from current_date()) 
    then 'Current Month'
    else 'Historical'
  end as time_recency
from agg
where trip_count >= 1
order by
  trip_year desc,
  trip_month desc,
  trip_count desc,
  case 
    when duration_bucket like '0-5%' then 1
    when duration_bucket like '5-10%' then 2
    when duration_bucket like '10-15%' then 3
    when duration_bucket like '15-20%' then 4
    when duration_bucket like '20-30%' then 5
    when duration_bucket like '30-45%' then 6
    when duration_bucket like '45-60%' then 7
    when duration_bucket like '1-2%' then 8
    else 9
  end