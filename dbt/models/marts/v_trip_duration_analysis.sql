-- models/marts/gold/v_trip_duration_analysis.sql
{{ config(
    materialized='view',
    tags=['gold', 'kpi', 'trip_duration_analysis'],
    enabled=true
) }}

-- COMPLETE TRIP DURATION ANALYSIS VIEW
WITH trips AS (
    SELECT
        trip_id,
        duration_seconds,
        age,
        usertype,
        starttime,
        start_station_id,
        end_station_id,
        
        -- Use pre-computed columns from fct_trips
        trip_month,
        trip_year,
        hour_of_day,
        peak_period,
        day_type,
        season
        
    FROM {{ ref('fct_trips') }}
    WHERE duration_seconds IS NOT NULL
      AND duration_seconds BETWEEN 60 AND 86400
      AND data_quality_tier IN ('High Quality', 'Medium Quality')
),

bucketed AS (
    SELECT
        trip_id,
        
        CASE
            WHEN duration_seconds < 300 THEN '0-5 min (Quick Ride)'
            WHEN duration_seconds < 600 THEN '5-10 min (Short Commute)'
            WHEN duration_seconds < 900 THEN '10-15 min (Standard Trip)'
            WHEN duration_seconds < 1200 THEN '15-20 min (Extended Ride)'
            WHEN duration_seconds < 1800 THEN '20-30 min (Leisure)'
            WHEN duration_seconds < 2700 THEN '30-45 min (Long Ride)'
            WHEN duration_seconds < 3600 THEN '45-60 min (Tour)'
            WHEN duration_seconds < 7200 THEN '1-2 hours (Extended Tour)'
            ELSE '2+ hours (Premium Rental)'
        END AS duration_bucket,
        
        CASE
            WHEN duration_seconds < 180 THEN 'Micro Ride (<3min)'
            WHEN duration_seconds BETWEEN 180 AND 600 THEN 'Short Ride (3-10min)'
            WHEN duration_seconds BETWEEN 600 AND 1800 THEN 'Standard Ride (10-30min)'
            WHEN duration_seconds BETWEEN 1800 AND 3600 THEN 'Long Ride (30-60min)'
            ELSE 'Extended Ride (>60min)'
        END AS duration_sub_bucket,
        
        duration_seconds,
        age,
        usertype,
        hour_of_day,
        day_type,
        peak_period,
        season,
        start_station_id,
        end_station_id,
        trip_month,
        trip_year,
        
        CASE 
            WHEN hour_of_day BETWEEN 6 AND 10 THEN 'Morning'
            WHEN hour_of_day BETWEEN 11 AND 15 THEN 'Afternoon'
            WHEN hour_of_day BETWEEN 16 AND 20 THEN 'Evening'
            ELSE 'Night'
        END AS day_segment
        
    FROM trips
),

agg AS (
    SELECT
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
        
        COUNT(trip_id) AS trip_count,
        COUNT(DISTINCT start_station_id) AS unique_start_stations,
        COUNT(DISTINCT end_station_id) AS unique_end_stations,
        ROUND(AVG(age), 2) AS avg_rider_age,
        ROUND(AVG(duration_seconds) / 60, 2) AS avg_duration_minutes,
        ROUND(MIN(duration_seconds) / 60, 2) AS min_duration_minutes,
        ROUND(MAX(duration_seconds) / 60, 2) AS max_duration_minutes,
        
        ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER(), 0), 3) AS pct_of_total_trips
        
    FROM bucketed
    GROUP BY 
        duration_bucket, duration_sub_bucket, usertype, day_type, 
        peak_period, season, hour_of_day, trip_month, trip_year, day_segment
)

SELECT
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
    
    RANK() OVER(PARTITION BY duration_bucket ORDER BY trip_count DESC) AS bucket_popularity_rank,
    RANK() OVER(PARTITION BY usertype ORDER BY trip_count DESC) AS user_type_rank,
    RANK() OVER(PARTITION BY season ORDER BY trip_count DESC) AS seasonal_rank,
    RANK() OVER(PARTITION BY trip_year, trip_month ORDER BY trip_count DESC) AS monthly_rank,
    
    CASE 
        WHEN trip_count > 1000 THEN 'High Volume'
        WHEN trip_count > 500 THEN 'Medium Volume'
        WHEN trip_count > 100 THEN 'Low Volume'
        ELSE 'Niche'
    END AS volume_category,
    
    CASE 
        WHEN avg_duration_minutes < 10 THEN 'Quick Trips'
        WHEN avg_duration_minutes BETWEEN 10 AND 20 THEN 'Standard Trips'
        WHEN avg_duration_minutes BETWEEN 20 AND 40 THEN 'Extended Trips'
        ELSE 'Long Duration'
    END AS duration_profile,
    
    CASE 
        WHEN trip_month = EXTRACT(MONTH FROM CURRENT_DATE()) 
         AND trip_year = EXTRACT(YEAR FROM CURRENT_DATE()) 
        THEN 'Current Month'
        ELSE 'Historical'
    END AS time_recency,
    
    CASE trip_month
        WHEN 1 THEN 'January'
        WHEN 2 THEN 'February'
        WHEN 3 THEN 'March'
        WHEN 4 THEN 'April'
        WHEN 5 THEN 'May'
        WHEN 6 THEN 'June'
        WHEN 7 THEN 'July'
        WHEN 8 THEN 'August'
        WHEN 9 THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
    END AS month_name,
    
    CASE 
        WHEN trip_month IN (1,2,3) THEN 'Q1'
        WHEN trip_month IN (4,5,6) THEN 'Q2'
        WHEN trip_month IN (7,8,9) THEN 'Q3'
        WHEN trip_month IN (10,11,12) THEN 'Q4'
    END AS quarter,
    
    CONCAT(trip_year, '-', LPAD(trip_month, 2, '0')) AS year_month,
    
    CASE 
        WHEN hour_of_day BETWEEN 0 AND 5 THEN 'Late Night (0-5)'
        WHEN hour_of_day BETWEEN 6 AND 10 THEN 'Morning (6-10)'
        WHEN hour_of_day BETWEEN 11 AND 15 THEN 'Afternoon (11-15)'
        WHEN hour_of_day BETWEEN 16 AND 20 THEN 'Evening (16-20)'
        ELSE 'Night (21-23)'
    END AS hour_segment,
    
    ROUND(avg_duration_minutes * 1.0 / NULLIF(unique_start_stations, 0), 2) AS avg_duration_per_station,
    
    CASE 
        WHEN avg_duration_minutes < 5 AND peak_period LIKE '%Peak%' THEN 'Quick Commute'
        WHEN avg_duration_minutes > 30 AND day_type = 'Weekend' THEN 'Leisurely Weekend Ride'
        WHEN avg_duration_minutes BETWEEN 10 AND 20 AND usertype = 'Subscriber' THEN 'Standard Commute'
        ELSE 'Regular Ride'
    END AS ride_pattern

FROM agg
WHERE trip_count >= 1

ORDER BY
    trip_year DESC,
    trip_month DESC,
    trip_count DESC,
    CASE 
        WHEN duration_bucket LIKE '0-5%' THEN 1
        WHEN duration_bucket LIKE '5-10%' THEN 2
        WHEN duration_bucket LIKE '10-15%' THEN 3
        WHEN duration_bucket LIKE '15-20%' THEN 4
        WHEN duration_bucket LIKE '20-30%' THEN 5
        WHEN duration_bucket LIKE '30-45%' THEN 6
        WHEN duration_bucket LIKE '45-60%' THEN 7
        WHEN duration_bucket LIKE '1-2%' THEN 8
        ELSE 9
    END