-- models/marts/gold/v_hourly_station_activity.sql
{{ config(
    materialized='view',
    tags=['gold', 'kpi', 'v_hourly_station_activity'],
    enabled=true
) }}

-- SIMPLIFIED VERSION - Reduced complexity for better performance
WITH hourly_activity AS (
    -- Departures only (arrivals not needed for basic analysis)
    SELECT
        start_station_id AS station_id,
        DATE_TRUNC('hour', starttime) AS hour_ts,
        trip_year,
        trip_month,
        trip_day,
        hour_of_day,
        1 AS trips_count,
        CASE WHEN usertype = 'Subscriber' THEN 1 ELSE 0 END AS subscriber_flag
        
    FROM {{ ref('fct_trips') }}
    WHERE start_station_id IS NOT NULL
      AND starttime IS NOT NULL
      AND data_quality_tier IN ('High Quality', 'Medium Quality')
),

aggregated_hourly AS (
    SELECT
        station_id,
        hour_ts,
        trip_year AS year,
        trip_month AS month,
        trip_day AS day,
        hour_of_day,
        
        -- Basic metrics only
        SUM(trips_count) AS departures,
        SUM(subscriber_flag) AS subscriber_departures,
        COUNT(*) - SUM(subscriber_flag) AS customer_departures,
        
        -- Simple classification
        CASE 
            WHEN SUM(trips_count) > 20 THEN 'High Activity'
            WHEN SUM(trips_count) > 10 THEN 'Medium Activity'
            WHEN SUM(trips_count) > 5 THEN 'Low Activity'
            ELSE 'Very Low Activity'
        END AS activity_level
        
    FROM hourly_activity
    WHERE station_id IS NOT NULL
      AND hour_ts IS NOT NULL
    GROUP BY station_id, hour_ts, trip_year, trip_month, trip_day, hour_of_day
    HAVING SUM(trips_count) > 0  -- Only hours with activity
),

station_info AS (
    SELECT
        station_id,
        station_name,
        performance_tier
    FROM {{ ref('dim_stations') }}
    WHERE station_id IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY station_id ORDER BY last_activity_date DESC) = 1
)

SELECT
    -- Station info
    ah.station_id,
    si.station_name,
    si.performance_tier,
    
    -- Time dimensions
    ah.hour_ts AS activity_hour_ts,
    ah.year,
    ah.month,
    ah.day,
    ah.hour_of_day,
    
    -- Basic activity metrics
    ah.departures,
    ah.subscriber_departures,
    ah.customer_departures,
    ah.activity_level,
    
    -- Simple peak classification
    CASE
        WHEN ah.hour_of_day BETWEEN 7 AND 9 THEN 'Morning Peak'
        WHEN ah.hour_of_day BETWEEN 17 AND 19 THEN 'Evening Peak'
        ELSE 'Off-Peak'
    END AS peak_period,
    
    -- Day type
    CASE 
        WHEN EXTRACT(DOW FROM ah.hour_ts) IN (0,6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type,
    
    -- Month name for Power BI
    CASE ah.month
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
    END AS month_name

FROM aggregated_hourly ah
LEFT JOIN station_info si ON TRIM(ah.station_id) = TRIM(si.station_id)

WHERE ah.station_id IS NOT NULL

ORDER BY 
    ah.year DESC,
    ah.month DESC,
    ah.day DESC,
    ah.hour_of_day DESC