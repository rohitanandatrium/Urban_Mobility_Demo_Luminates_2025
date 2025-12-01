-- models/marts/fct_trips.sql
-- ==========================================================
-- **OPTIMIZED FACT TABLE - PRE-COMPUTED FOR ALL VIEWS**
-- Stage se pre-calculated values direct use
-- Views ke liye sab calculations yahi pehle se compute
-- ==========================================================

{{ config(
    materialized='table',
    cluster_by=['trip_year', 'trip_month'],
    partition_by={
        'field': 'starttime',
        'data_type': 'timestamp',
        'granularity': 'month'
    }
) }}

WITH 
-- ==========================================================
-- STAGE DATA DIRECTLY (NO RECALCULATION)
-- ==========================================================
stage_data AS (
    SELECT
        -- Unique Trip ID
        md5(
            concat_ws('|',
                COALESCE(CAST(starttime AS STRING), ''),
                COALESCE(CAST(stoptime AS STRING), ''),
                COALESCE(bikeid, ''),
                COALESCE(start_station_id, ''),
                COALESCE(end_station_id, ''),
                COALESCE(CAST(FILE_ROW_NUMBER AS STRING), '')
            )
        ) AS trip_id,
        
        -- All pre-calculated columns from staging
        tripduration AS duration_seconds,  -- Already calculated in staging
        starttime,
        stoptime,
        start_station_id,
        start_station_name,
        end_station_id,
        end_station_name,
        bikeid,
        usertype,
        birth_year,
        gender,
        gender_category,  -- Already in staging
        age,              -- Already in staging
        age_group,        -- Already in staging
        month_name,       -- Already in staging
        
        -- Coordinates
        start_latitude,
        start_longitude,
        end_latitude,
        end_longitude,
        
        -- Metadata
        FILENAME,
        FILE_MODIFIED_TIME,
        FILE_ROW_NUMBER,
        LOAD_ID,
        LOADED_AT,
        data_quality_tier
        
    FROM {{ ref('stg_citibike_trips') }}
    WHERE data_quality_tier IN ('High Quality', 'Medium Quality')
      AND starttime IS NOT NULL
      AND stoptime IS NOT NULL
      AND tripduration BETWEEN 60 AND 14400    -- Realistic trips only
),

-- ==========================================================
-- **PRE-COMPUTE EVERYTHING VIEWS WILL NEED**
-- ==========================================================
pre_computed AS (
    SELECT
        -- Core identifiers
        trip_id,
        
        -- Basic trip data (from staging)
        duration_seconds,
        starttime,
        stoptime,
        start_station_id,
        start_station_name,
        end_station_id,
        end_station_name,
        bikeid,
        usertype,
        birth_year,
        gender,
        gender_category,
        age,
        age_group,
        month_name,
        start_latitude,
        start_longitude,
        end_latitude,
        end_longitude,
        
        -- Metadata
        FILENAME,
        FILE_MODIFIED_TIME,
        FILE_ROW_NUMBER,
        LOAD_ID,
        LOADED_AT,
        data_quality_tier,
        
        -- ==============================================
        -- **TIME-BASED DIMENSIONS (Views ke liye)**
        -- ==============================================
        EXTRACT(YEAR FROM starttime) AS trip_year,
        EXTRACT(MONTH FROM starttime) AS trip_month,
        EXTRACT(DAY FROM starttime) AS trip_day,
        EXTRACT(HOUR FROM starttime) AS hour_of_day,
        EXTRACT(MINUTE FROM starttime) AS minute_of_hour,
        EXTRACT(DOW FROM starttime) + 1 AS day_of_week,  -- 1=Sunday
        
        -- Day type classification
        CASE 
            WHEN EXTRACT(DOW FROM starttime) IN (0,6) THEN 'Weekend'
            ELSE 'Weekday'
        END AS day_type,
        
        -- Peak period classification
        CASE
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 7 AND 9 THEN 'Morning Peak (7-9 AM)'
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 17 AND 19 THEN 'Evening Peak (5-7 PM)'
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 12 AND 14 THEN 'Lunch Peak (12-2 PM)'
            ELSE 'Off-Peak'
        END AS peak_period,
        
        -- Season classification
        CASE 
            WHEN EXTRACT(MONTH FROM starttime) IN (12,1,2) THEN 'Winter'
            WHEN EXTRACT(MONTH FROM starttime) IN (3,4,5) THEN 'Spring' 
            WHEN EXTRACT(MONTH FROM starttime) IN (6,7,8) THEN 'Summer'
            ELSE 'Fall'
        END AS season,
        
        -- Day segment
        CASE 
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 6 AND 10 THEN 'Morning'
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 11 AND 15 THEN 'Afternoon'
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 16 AND 20 THEN 'Evening'
            ELSE 'Night'
        END AS day_segment,
        
        -- ==============================================
        -- **GEOGRAPHIC CALCULATIONS (Views ke liye)**
        -- ==============================================
        -- Approximate distance in KM
        CASE
            WHEN start_latitude IS NOT NULL AND start_longitude IS NOT NULL 
                 AND end_latitude IS NOT NULL AND end_longitude IS NOT NULL
            THEN ROUND(
                SQRT(
                    POWER((end_latitude - start_latitude) * 111.32, 2) +  -- 1 degree lat ≈ 111.32 km
                    POWER((end_longitude - start_longitude) * 85.0, 2)     -- 1 degree long ≈ 85.0 km at NYC lat
                ), 2
            )
            ELSE NULL
        END AS approx_distance_km,
        
        -- Route ID for popular routes view
        CASE
            WHEN start_station_id IS NOT NULL AND end_station_id IS NOT NULL 
                 AND start_station_id != end_station_id
            THEN md5(start_station_id || '|' || end_station_id)
            ELSE NULL
        END AS route_id,
        
        -- ==============================================
        -- **DURATION ANALYTICS (Views ke liye)**
        -- ==============================================
        -- Duration buckets (for trip_duration_analysis view)
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
        
        -- Minutes per KM (efficiency metric)
        CASE
            WHEN duration_seconds IS NOT NULL AND 
                 start_latitude IS NOT NULL AND end_latitude IS NOT NULL
            THEN ROUND((duration_seconds / 60.0) / 
                  NULLIF(SQRT(
                      POWER((end_latitude - start_latitude) * 111.32, 2) + 
                      POWER((end_longitude - start_longitude) * 85.0, 2)
                  ), 0), 2)
            ELSE NULL
        END AS minutes_per_km,
        
        -- ==============================================
        -- **USER ANALYTICS (Views ke liye)**
        -- ==============================================
        -- User type simplified
        CASE 
            WHEN LOWER(usertype) = 'subscriber' THEN 'Subscriber'
            WHEN LOWER(usertype) IN ('customer', 'casual') THEN 'Customer'
            ELSE 'Unknown'
        END AS user_type_clean,
        
        -- Gender numeric to text
        CASE 
            WHEN gender = 1 THEN 'Male'
            WHEN gender = 2 THEN 'Female'
            ELSE 'Not Specified'
        END AS gender_text,
        
        -- ==============================================
        -- **BUSINESS LOGIC FLAGS (Views ke liye)**
        -- ==============================================
        -- Trip type
        CASE 
            WHEN start_station_id = end_station_id THEN 'Round Trip'
            ELSE 'Point-to-Point'
        END AS trip_type,
        
        -- Duration validation
        CASE
            WHEN duration_seconds < 60 THEN 'Suspiciously Short (<1 min)'
            WHEN duration_seconds > 86400 THEN 'Suspiciously Long (>24 hours)'
            ELSE 'Normal Duration'
        END AS duration_validation,
        
        -- Bike performance tier
        CASE 
            WHEN duration_seconds BETWEEN 300 AND 1800 
                 AND EXTRACT(HOUR FROM starttime) BETWEEN 7 AND 19 
            THEN 'Prime Commute'
            WHEN duration_seconds > 1800 
                 AND EXTRACT(DOW FROM starttime) IN (0,6) 
            THEN 'Weekend Leisure'
            WHEN duration_seconds < 300 THEN 'Quick Ride'
            ELSE 'Standard Trip'
        END AS trip_profile,
        
        -- Data freshness
        CASE
            WHEN starttime >= CURRENT_DATE() - 7 THEN 'Recent (Last 7 Days)'
            WHEN starttime >= CURRENT_DATE() - 30 THEN 'Current (Last 30 Days)'
            WHEN starttime >= CURRENT_DATE() - 90 THEN 'Recent Historical (Last 90 Days)'
            ELSE 'Historical'
        END AS data_freshness,
        
        -- Operational flags
        CASE
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 7 AND 9 
                 AND data_quality_tier = 'High Quality' THEN 'Morning Peak Quality'
            WHEN EXTRACT(HOUR FROM starttime) BETWEEN 17 AND 19 
                 AND data_quality_tier = 'High Quality' THEN 'Evening Peak Quality'
            ELSE 'Standard Record'
        END AS operational_value,
        
        -- Partition keys for performance
        DATE_TRUNC('month', starttime) AS month_partition_key,
        DATE_TRUNC('week', starttime) AS week_partition_key

    FROM stage_data
)

-- ==========================================================
-- FINAL OUTPUT - READY FOR ALL VIEWS
-- ==========================================================
SELECT
    -- Core identifiers
    trip_id,
    route_id,
    
    -- Temporal dimensions (pre-computed)
    starttime,
    stoptime,
    trip_year,
    trip_month,
    trip_day,
    hour_of_day,
    minute_of_hour,
    day_of_week,
    day_type,
    peak_period,
    season,
    day_segment,
    month_partition_key,
    week_partition_key,
    
    -- Trip metrics
    duration_seconds,
    duration_bucket,
    duration_sub_bucket,
    duration_validation,
    approx_distance_km,
    minutes_per_km,
    
    -- Station information
    start_station_id,
    start_station_name,
    end_station_id,
    end_station_name,
    start_latitude,
    start_longitude,
    end_latitude,
    end_longitude,
    
    -- User information
    bikeid,
    usertype AS original_usertype,
    user_type_clean AS usertype,
    birth_year,
    gender,
    gender_text,
    gender_category,
    age,
    age_group,
    
    -- Trip characteristics
    trip_type,
    trip_profile,
    
    -- Data quality
    data_quality_tier,
    operational_value,
    data_freshness,
    
    -- Metadata
    FILENAME,
    FILE_MODIFIED_TIME,
    FILE_ROW_NUMBER,
    LOAD_ID,
    LOADED_AT,
    month_name
    
FROM pre_computed
WHERE duration_seconds IS NOT NULL
  AND starttime IS NOT NULL
  AND start_station_id IS NOT NULL
  AND end_station_id IS NOT NULL
ORDER BY starttime DESC, data_quality_tier DESC