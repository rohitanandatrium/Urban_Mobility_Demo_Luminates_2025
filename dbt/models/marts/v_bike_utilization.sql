-- models/marts/gold/v_bike_utilization.sql
{{ config(
    materialized='view',
    tags=['gold', 'kpi', 'v_bike_utilization'],
    enabled=true
) }}

WITH bike_daily_stats AS (
    SELECT
        bikeid,
        DATE(starttime) AS trip_date,
        trip_year,
        trip_month,
        month_name,
        
        COUNT(*) AS trips_per_day,
        SUM(duration_seconds) / 3600.0 AS total_hours_per_day,
        
        SUM(CASE WHEN usertype = 'Subscriber' THEN 1 ELSE 0 END) AS subscriber_trips,
        SUM(CASE WHEN usertype = 'Customer' THEN 1 ELSE 0 END) AS customer_trips,
        
        COUNT(DISTINCT start_station_id) AS unique_start_stations,
        COUNT(DISTINCT end_station_id) AS unique_end_stations,
        
        MIN(starttime) AS first_trip_time,
        MAX(starttime) AS last_trip_time,
        AVG(duration_seconds) AS avg_duration_seconds
        
    FROM {{ ref('fct_trips') }}
    WHERE bikeid IS NOT NULL
      AND starttime IS NOT NULL
      AND stoptime IS NOT NULL
      AND duration_seconds BETWEEN 60 AND 86400
      AND data_quality_tier IN ('High Quality', 'Medium Quality')
    GROUP BY bikeid, DATE(starttime), trip_year, trip_month, month_name
),

-- Get recent month name separately
recent_months AS (
    SELECT
        bikeid,
        month_name AS recent_month_name,
        ROW_NUMBER() OVER (PARTITION BY bikeid ORDER BY trip_date DESC) AS rn
    FROM bike_daily_stats
),

bike_summary AS (
    SELECT
        bd.bikeid,
        
        COUNT(*) AS total_days_active,
        SUM(bd.trips_per_day) AS total_trips,
        ROUND(SUM(bd.total_hours_per_day), 2) AS total_hours_in_use,
        
        ROUND(AVG(bd.trips_per_day), 2) AS avg_trips_per_day,
        ROUND(AVG(bd.total_hours_per_day), 2) AS avg_hours_per_day,
        ROUND(AVG(bd.avg_duration_seconds), 2) AS avg_trip_duration_seconds,
        
        SUM(bd.subscriber_trips) AS total_subscriber_trips,
        SUM(bd.customer_trips) AS total_customer_trips,
        ROUND(100.0 * SUM(bd.subscriber_trips) / NULLIF(SUM(bd.trips_per_day), 0), 2) AS overall_pct_subscriber,
        
        MAX(bd.unique_start_stations) AS max_daily_stations_used,
        ROUND(AVG(bd.unique_start_stations), 2) AS avg_daily_stations_used,
        
        MIN(bd.trip_date) AS first_activity_date,
        MAX(bd.trip_date) AS last_activity_date,
        
        COUNT(DISTINCT bd.trip_year || '-' || LPAD(bd.trip_month, 2, '0')) AS active_months,
        
        rm.recent_month_name
        
    FROM bike_daily_stats bd
    LEFT JOIN recent_months rm 
        ON bd.bikeid = rm.bikeid 
        AND rm.rn = 1
    WHERE bd.trips_per_day > 0
    GROUP BY bd.bikeid, rm.recent_month_name
),

bike_intelligence AS (
    SELECT
        bs.bikeid,
        
        bs.total_trips,
        bs.total_hours_in_use,
        bs.avg_trips_per_day,
        bs.avg_hours_per_day,
        ROUND(bs.avg_trip_duration_seconds / 60, 2) AS avg_trip_duration_minutes,
        
        CASE 
            WHEN bs.total_trips > 2000 THEN 'High Performance'
            WHEN bs.total_trips BETWEEN 1000 AND 2000 THEN 'Medium Performance' 
            WHEN bs.total_trips BETWEEN 500 AND 999 THEN 'Low Performance'
            ELSE 'Underutilized'
        END AS performance_tier,
        
        bs.total_days_active AS active_days,
        bs.active_months,
        ROUND(bs.total_trips * 1.0 / NULLIF(bs.total_days_active, 0), 2) AS trips_per_active_day,
        
        bs.overall_pct_subscriber,
        bs.total_subscriber_trips,
        bs.total_customer_trips,
        
        bs.max_daily_stations_used,
        bs.avg_daily_stations_used,
        
        bs.first_activity_date,
        bs.last_activity_date,
        bs.recent_month_name,
        
        DATEDIFF('day', bs.first_activity_date, bs.last_activity_date) AS operational_days,
        
        ROUND(100.0 * bs.total_hours_in_use / NULLIF(
            DATEDIFF('day', bs.first_activity_date, bs.last_activity_date) * 24, 0
        ), 2) AS utilization_percentage
        
    FROM bike_summary bs
    WHERE bs.total_trips >= 1
)

SELECT
    bikeid,
    total_trips,
    total_hours_in_use,
    avg_trips_per_day,
    avg_hours_per_day,
    avg_trip_duration_minutes,
    
    performance_tier,
    active_days,
    active_months,
    trips_per_active_day,
    operational_days,
    utilization_percentage,
    
    overall_pct_subscriber,
    total_subscriber_trips,
    total_customer_trips,
    max_daily_stations_used,
    avg_daily_stations_used,
    first_activity_date,
    last_activity_date,
    recent_month_name,
    
    CASE MONTH(first_activity_date)
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
    END AS first_activity_month,
    
    CASE MONTH(last_activity_date)
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
    END AS last_activity_month,
    
    CASE 
        WHEN last_activity_date < CURRENT_DATE() - 90 THEN 'INACTIVE (>90 days)'
        WHEN last_activity_date < CURRENT_DATE() - 30 THEN 'Inactive > 30 days'
        WHEN avg_trips_per_day < 0.5 THEN 'Low Usage'
        WHEN performance_tier = 'Underutilized' AND total_trips > 100 THEN 'Underperforming'
        WHEN utilization_percentage < 5 THEN 'Low Utilization'
        ELSE 'Normal Operation'
    END AS maintenance_flag,
    
    CASE 
        WHEN total_trips > 1000 AND avg_trips_per_day > 5 THEN 'Top Performer'
        WHEN total_trips BETWEEN 500 AND 1000 AND avg_trips_per_day > 3 THEN 'Reliable Workhorse'
        WHEN total_trips < 100 AND DATEDIFF('day', first_activity_date, last_activity_date) > 180 THEN 'Occasional Use'
        ELSE 'Standard Bike'
    END AS bike_profile,
    
    CASE 
        WHEN active_months >= 6 THEN 'Year-round Usage'
        WHEN active_months BETWEEN 3 AND 5 THEN 'Seasonal Usage'
        ELSE 'Limited Usage'
    END AS usage_pattern,
    
    CASE 
        WHEN last_activity_date >= CURRENT_DATE() - 7 THEN 'Active Recently'
        WHEN last_activity_date >= CURRENT_DATE() - 30 THEN 'Active This Month'
        WHEN last_activity_date >= CURRENT_DATE() - 90 THEN 'Active Last Quarter'
        ELSE 'Inactive'
    END AS current_status,
    
    ROUND(
        (total_trips * 0.0005) + 
        (active_months * 2) + 
        (utilization_percentage * 0.3) + 
        (CASE WHEN last_activity_date >= CURRENT_DATE() - 30 THEN 20 ELSE 0 END),
        0
    ) AS efficiency_score,
    
    RANK() OVER (ORDER BY total_trips DESC) AS rank_by_trips,
    RANK() OVER (ORDER BY total_hours_in_use DESC) AS rank_by_hours,
    RANK() OVER (ORDER BY avg_trips_per_day DESC) AS rank_by_daily_usage
    
FROM bike_intelligence
WHERE bikeid IS NOT NULL
  AND total_trips >= 1

ORDER BY 
    total_trips DESC,
    last_activity_date DESC