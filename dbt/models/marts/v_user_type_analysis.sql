-- models/marts/gold/v_user_type_analysis.sql
{{ config(
    materialized='view',
    tags=['gold','kpi','user_type_analysis']
) }}

with trips as (
  select
    trip_id,
    usertype,
    duration_seconds,
    starttime,
    age,
    start_station_id,
    end_station_id,
    extract(year from starttime) as trip_year,
    extract(month from starttime) as trip_month,
    extract(day from starttime) as trip_day,
    bikeid,
    gender,
    case 
      when extract(dow from starttime) in (0,6) then 'Weekend'
      else 'Weekday'
    end as day_type,
    case 
      when extract(month from starttime) in (12,1,2) then 'Winter'
      when extract(month from starttime) in (3,4,5) then 'Spring' 
      when extract(month from starttime) in (6,7,8) then 'Summer'
      else 'Fall'
    end as season
  from {{ ref('fct_trips') }}
  where usertype is not null
    and duration_seconds between 60 and 86400
),

hourly_analysis as (
  select
    usertype,
    extract(hour from starttime) as hour_of_day,
    extract(minute from starttime) as minute_of_hour,
    trip_year,
    trip_month,
    trip_day,
    day_type,
    season,
    gender,
    
    case
      when extract(hour from starttime) between 7 and 9 then 
        case 
          when extract(hour from starttime) = 7 then 'Early Morning Peak (7 AM)'
          when extract(hour from starttime) = 8 then 'Core Morning Peak (8 AM)'
          when extract(hour from starttime) = 9 then 'Late Morning Peak (9 AM)'
        end
      when extract(hour from starttime) between 17 and 19 then 
        case
          when extract(hour from starttime) = 17 then 'Early Evening Peak (5 PM)'
          when extract(hour from starttime) = 18 then 'Core Evening Peak (6 PM)'
          when extract(hour from starttime) = 19 then 'Late Evening Peak (7 PM)'
        end
      when extract(hour from starttime) between 12 and 14 then 'Lunch Peak'
      when extract(hour from starttime) between 0 and 5 then 'Late Night'
      when extract(hour from starttime) between 22 and 23 then 'Night'
      else 'Regular Off-Peak'
    end as peak_period_detail,
    
    case 
      when extract(hour from starttime) between 6 and 10 then 'Morning'
      when extract(hour from starttime) between 11 and 15 then 'Afternoon'
      when extract(hour from starttime) between 16 and 20 then 'Evening'
      else 'Night'
    end as day_segment,
    
    count(trip_id) as trip_count,
    count(distinct bikeid) as unique_bikes_used,
    count(distinct start_station_id) as unique_start_stations,
    count(distinct end_station_id) as unique_end_stations,
    round(avg(duration_seconds), 2) as avg_duration_seconds,
    round(min(duration_seconds), 2) as min_duration_seconds,
    round(max(duration_seconds), 2) as max_duration_seconds,
    round(avg(age), 2) as avg_rider_age,
    round(stddev(age), 2) as age_std_dev,
    
    count(case when duration_seconds < 300 then 1 end) as quick_rides,
    count(case when duration_seconds between 300 and 900 then 1 end) as short_rides,
    count(case when duration_seconds between 900 and 1800 then 1 end) as medium_rides,
    count(case when duration_seconds > 1800 then 1 end) as long_rides

  from trips
  group by 
    usertype, hour_of_day, minute_of_hour, trip_year, trip_month, 
    trip_day, day_type, season, gender, peak_period_detail, day_segment
),

user_summaries as (
  select
    usertype,
    trip_year,
    trip_month,
    gender,
    season,
    
    sum(trip_count) as total_trips,
    sum(unique_bikes_used) as total_bikes_used,
    sum(unique_start_stations) as total_start_stations_used,
    sum(unique_end_stations) as total_end_stations_used,
    round(avg(avg_duration_seconds), 2) as overall_avg_duration,
    round(avg(avg_rider_age), 2) as overall_avg_age,
    
    sum(case when peak_period_detail like '%Peak%' then trip_count else 0 end) as peak_trips,
    sum(case when peak_period_detail = 'Regular Off-Peak' then trip_count else 0 end) as off_peak_trips,
    round(100.0 * sum(case when peak_period_detail like '%Peak%' then trip_count else 0 end) / nullif(sum(trip_count), 0), 2) as pct_peak_trips,
    
    sum(quick_rides) as total_quick_rides,
    sum(short_rides) as total_short_rides,
    sum(medium_rides) as total_medium_rides,
    sum(long_rides) as total_long_rides,
    
    count(distinct trip_day) as active_days,
    count(distinct hour_of_day) as active_hours

  from hourly_analysis
  group by usertype, trip_year, trip_month, gender, season
)

select
  ha.usertype,
  ha.trip_year,
  ha.trip_month, 
  ha.trip_day,
  ha.hour_of_day,
  ha.minute_of_hour,
  ha.gender,
  ha.season,
  ha.day_type,
  ha.peak_period_detail,
  ha.day_segment,
  
  ha.trip_count as hourly_trips,
  ha.unique_bikes_used,
  ha.unique_start_stations,
  ha.unique_end_stations,
  ha.avg_duration_seconds as hourly_avg_duration,
  ha.min_duration_seconds as hourly_min_duration,
  ha.max_duration_seconds as hourly_max_duration,
  ha.avg_rider_age as hourly_avg_age,
  ha.age_std_dev,
  ha.quick_rides,
  ha.short_rides,
  ha.medium_rides,
  ha.long_rides,
  
  us.total_trips,
  us.total_bikes_used,
  us.total_start_stations_used,
  us.total_end_stations_used,
  us.overall_avg_duration,
  us.overall_avg_age,
  us.peak_trips,
  us.off_peak_trips,
  us.pct_peak_trips,
  us.total_quick_rides,
  us.total_short_rides,
  us.total_medium_rides,
  us.total_long_rides,
  us.active_days,
  us.active_hours,
  
  round(100.0 * ha.trip_count / nullif(us.total_trips, 0), 4) as pct_of_user_total,
  round(100.0 * ha.trip_count / nullif(us.total_trips, 0), 4) as hourly_concentration,
  
  case 
    when ha.peak_period_detail like '%Peak%' and ha.trip_count > avg(ha.trip_count) over(partition by ha.usertype, ha.hour_of_day) then 'High Peak Usage'
    when ha.peak_period_detail like '%Peak%' then 'Normal Peak Usage'
    when ha.trip_count > avg(ha.trip_count) over(partition by ha.usertype, ha.hour_of_day) then 'High Off-Peak Usage'
    else 'Normal Off-Peak Usage'
  end as usage_pattern,
  
  case 
    when ha.trip_count > 50 then 'Very High Traffic'
    when ha.trip_count > 20 then 'High Traffic'
    when ha.trip_count > 10 then 'Medium Traffic'
    when ha.trip_count > 5 then 'Low Traffic'
    else 'Minimal Traffic'
  end as traffic_intensity,
  
  case 
    when ha.trip_year = extract(year from current_date()) 
     and ha.trip_month = extract(month from current_date())
    then 'Current Month'
    else 'Historical'
  end as data_recency,
  
  md5(concat_ws('|', 
    ha.usertype, ha.trip_year, ha.trip_month, ha.trip_day, 
    ha.hour_of_day, ha.minute_of_hour, ha.gender, ha.season
  )) as analysis_id

from hourly_analysis ha
join user_summaries us 
  on ha.usertype = us.usertype 
  and ha.trip_year = us.trip_year 
  and ha.trip_month = us.trip_month 
  and ha.gender = us.gender 
  and ha.season = us.season

where ha.trip_count >= 1
  and us.total_trips >= 1

order by 
  ha.trip_year desc,
  ha.trip_month desc,
  ha.trip_day desc,
  ha.hour_of_day desc,
  ha.trip_count desc