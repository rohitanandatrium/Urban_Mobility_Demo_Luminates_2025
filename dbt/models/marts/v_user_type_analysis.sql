-- models/marts/gold/v_user_type_analysis.sql
{{ config(
    materialized='view',
    tags=['gold', 'kpi', 'user_type_analysis'],
    enabled=true
) }}

WITH trips AS (
    SELECT
        trip_id,
        usertype,
        duration_seconds,
        starttime,
        age,
        start_station_id,
        end_station_id,
        bikeid,
        gender,
        trip_year,
        trip_month,
        trip_day,
        hour_of_day,
        minute_of_hour,
        day_type,
        season,
        peak_period
        
    FROM {{ ref('fct_trips') }}
    WHERE usertype IS NOT NULL
      AND duration_seconds BETWEEN 60 AND 86400
      AND data_quality_tier IN ('High Quality', 'Medium Quality')
),

hourly_analysis AS (
    SELECT
        usertype,
        hour_of_day,
        minute_of_hour,
        trip_year,
        trip_month,
        trip_day,
        day_type,
        season,
        gender,
        
        CASE
            WHEN hour_of_day = 7 THEN 'Early Morning Peak (7 AM)'
            WHEN hour_of_day = 8 THEN 'Core Morning Peak (8 AM)'
            WHEN hour_of_day = 9 THEN 'Late Morning Peak (9 AM)'
            WHEN hour_of_day = 17 THEN 'Early Evening Peak (5 PM)'
            WHEN hour_of_day = 18 THEN 'Core Evening Peak (6 PM)'
            WHEN hour_of_day = 19 THEN 'Late Evening Peak (7 PM)'
            WHEN hour_of_day BETWEEN 12 AND 14 THEN 'Lunch Peak'
            WHEN hour_of_day BETWEEN 0 AND 5 THEN 'Late Night'
            WHEN hour_of_day BETWEEN 22 AND 23 THEN 'Night'
            ELSE 'Regular Off-Peak'
        END AS peak_period_detail,
        
        CASE 
            WHEN hour_of_day BETWEEN 6 AND 10 THEN 'Morning'
            WHEN hour_of_day BETWEEN 11 AND 15 THEN 'Afternoon'
            WHEN hour_of_day BETWEEN 16 AND 20 THEN 'Evening'
            ELSE 'Night'
        END AS day_segment,
        
        COUNT(trip_id) AS trip_count,
        COUNT(DISTINCT bikeid) AS unique_bikes_used,
        COUNT(DISTINCT start_station_id) AS unique_start_stations,
        COUNT(DISTINCT end_station_id) AS unique_end_stations,
        ROUND(AVG(duration_seconds), 2) AS avg_duration_seconds,
        ROUND(MIN(duration_seconds), 2) AS min_duration_seconds,
        ROUND(MAX(duration_seconds), 2) AS max_duration_seconds,
        ROUND(AVG(age), 2) AS avg_rider_age,
        ROUND(STDDEV(age), 2) AS age_std_dev,
        
        COUNT(CASE WHEN duration_seconds < 300 THEN 1 END) AS quick_rides,
        COUNT(CASE WHEN duration_seconds BETWEEN 300 AND 900 THEN 1 END) AS short_rides,
        COUNT(CASE WHEN duration_seconds BETWEEN 900 AND 1800 THEN 1 END) AS medium_rides,
        COUNT(CASE WHEN duration_seconds > 1800 THEN 1 END) AS long_rides
        
    FROM trips
    GROUP BY 
        usertype, hour_of_day, minute_of_hour, trip_year, trip_month, 
        trip_day, day_type, season, gender
),

user_summaries AS (
    SELECT
        usertype,
        trip_year,
        trip_month,
        gender,
        season,
        
        SUM(trip_count) AS total_trips,
        SUM(unique_bikes_used) AS total_bikes_used,
        SUM(unique_start_stations) AS total_start_stations_used,
        SUM(unique_end_stations) AS total_end_stations_used,
        ROUND(AVG(avg_duration_seconds), 2) AS overall_avg_duration,
        ROUND(AVG(avg_rider_age), 2) AS overall_avg_age,
        
        SUM(CASE WHEN peak_period_detail LIKE '%Peak%' THEN trip_count ELSE 0 END) AS peak_trips,
        SUM(CASE WHEN peak_period_detail = 'Regular Off-Peak' THEN trip_count ELSE 0 END) AS off_peak_trips,
        ROUND(100.0 * SUM(CASE WHEN peak_period_detail LIKE '%Peak%' THEN trip_count ELSE 0 END) / NULLIF(SUM(trip_count), 0), 2) AS pct_peak_trips,
        
        SUM(quick_rides) AS total_quick_rides,
        SUM(short_rides) AS total_short_rides,
        SUM(medium_rides) AS total_medium_rides,
        SUM(long_rides) AS total_long_rides,
        
        COUNT(DISTINCT trip_day) AS active_days,
        COUNT(DISTINCT hour_of_day) AS active_hours
        
    FROM hourly_analysis
    GROUP BY usertype, trip_year, trip_month, gender, season
)

SELECT
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
    
    ha.trip_count AS hourly_trips,
    ha.unique_bikes_used,
    ha.unique_start_stations,
    ha.unique_end_stations,
    ha.avg_duration_seconds AS hourly_avg_duration,
    ha.min_duration_seconds AS hourly_min_duration,
    ha.max_duration_seconds AS hourly_max_duration,
    ha.avg_rider_age AS hourly_avg_age,
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
    
    ROUND(100.0 * ha.trip_count / NULLIF(us.total_trips, 0), 4) AS pct_of_user_total,
    
    CASE 
        WHEN ha.peak_period_detail LIKE '%Peak%' 
             AND ha.trip_count > AVG(ha.trip_count) OVER(PARTITION BY ha.usertype, ha.hour_of_day) 
        THEN 'High Peak Usage'
        WHEN ha.peak_period_detail LIKE '%Peak%' 
        THEN 'Normal Peak Usage'
        WHEN ha.trip_count > AVG(ha.trip_count) OVER(PARTITION BY ha.usertype, ha.hour_of_day) 
        THEN 'High Off-Peak Usage'
        ELSE 'Normal Off-Peak Usage'
    END AS usage_pattern,
    
    CASE 
        WHEN ha.trip_count > 50 THEN 'Very High Traffic'
        WHEN ha.trip_count > 20 THEN 'High Traffic'
        WHEN ha.trip_count > 10 THEN 'Medium Traffic'
        WHEN ha.trip_count > 5 THEN 'Low Traffic'
        ELSE 'Minimal Traffic'
    END AS traffic_intensity,
    
    CASE 
        WHEN ha.trip_year = EXTRACT(YEAR FROM CURRENT_DATE()) 
             AND ha.trip_month = EXTRACT(MONTH FROM CURRENT_DATE())
        THEN 'Current Month'
        ELSE 'Historical'
    END AS data_recency,
    
    CASE ha.gender
        WHEN 1 THEN 'Male'
        WHEN 2 THEN 'Female'
        ELSE 'Not Specified'
    END AS gender_text,
    
    ROUND(ha.trip_count * 1.0 / NULLIF(ha.unique_bikes_used, 0), 2) AS trips_per_bike_per_hour
    
FROM hourly_analysis ha
JOIN user_summaries us 
    ON ha.usertype = us.usertype 
    AND ha.trip_year = us.trip_year 
    AND ha.trip_month = us.trip_month 
    AND ha.gender = us.gender 
    AND ha.season = us.season

WHERE ha.trip_count >= 1
  AND us.total_trips >= 1

ORDER BY 
    ha.trip_year DESC,
    ha.trip_month DESC,
    ha.trip_day DESC,
    ha.hour_of_day DESC