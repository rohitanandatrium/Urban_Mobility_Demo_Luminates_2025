-- models/marts/gold/v_popular_routes.sql
{{ config(
    materialized='view',
    unique_key='route_id',
    tags=['gold', 'kpi', 'v_popular_routes'],
    enabled=true
) }}

WITH trips AS (
    SELECT
        start_station_id,
        end_station_id,
        usertype,
        starttime,
        bikeid,
        gender,
        peak_period,
        day_type,
        trip_month,
        trip_year
        
    FROM {{ ref('fct_trips') }}
    WHERE start_station_id IS NOT NULL
      AND end_station_id IS NOT NULL
      AND start_station_id != end_station_id
      AND data_quality_tier IN ('High Quality', 'Medium Quality')
),

route_intelligence AS (
    SELECT
        start_station_id,
        end_station_id,
        MD5(start_station_id || '|' || end_station_id) AS route_id,
        
        COUNT(*) AS trip_count,
        
        COUNT(CASE WHEN peak_period LIKE 'Morning Peak%' THEN 1 END) AS morning_peak_trips,
        COUNT(CASE WHEN peak_period LIKE 'Evening Peak%' THEN 1 END) AS evening_peak_trips,
        COUNT(CASE WHEN day_type = 'Weekend' THEN 1 END) AS weekend_trips,
        
        COUNT(CASE WHEN LOWER(usertype) = 'subscriber' THEN 1 END) AS subscriber_trips,
        COUNT(CASE WHEN LOWER(usertype) IN ('customer','casual') THEN 1 END) AS customer_trips,
        
        COUNT(CASE WHEN gender = 1 THEN 1 END) AS male_riders,
        COUNT(CASE WHEN gender = 2 THEN 1 END) AS female_riders,
        
        COUNT(DISTINCT bikeid) AS unique_bikes_used,
        
        COUNT(DISTINCT trip_month) AS active_months,
        COUNT(DISTINCT trip_year) AS active_years,
        MIN(starttime) AS first_trip_date,
        MAX(starttime) AS last_trip_date,
        
        CASE 
            WHEN COUNT(DISTINCT trip_month) >= 12 THEN 'Established (>1 year)'
            WHEN COUNT(DISTINCT trip_month) >= 6 THEN 'Established (6+ months)'
            WHEN COUNT(DISTINCT trip_month) >= 3 THEN 'Growing (3-6 months)'
            ELSE 'Emerging (<3 months)'
        END AS route_maturity,
        
        CASE 
            WHEN COUNT(*) > 1000 THEN 'Super Route (>1000)'
            WHEN COUNT(*) > 500 THEN 'Major Route (500-1000)'
            WHEN COUNT(*) > 100 THEN 'Medium Route (100-500)'
            WHEN COUNT(*) > 50 THEN 'Minor Route (50-100)'
            WHEN COUNT(*) > 10 THEN 'Small Route (10-50)'
            ELSE 'Niche Route (<10)'
        END AS route_volume_tier
        
    FROM trips
    GROUP BY start_station_id, end_station_id
),

route_analytics AS (
    SELECT
        ri.*,
        
        ROUND(100.0 * subscriber_trips / NULLIF(trip_count, 0), 2) AS pct_subscriber,
        ROUND(100.0 * customer_trips / NULLIF(trip_count, 0), 2) AS pct_customer,
        ROUND(100.0 * morning_peak_trips / NULLIF(trip_count, 0), 2) AS pct_morning_peak,
        ROUND(100.0 * evening_peak_trips / NULLIF(trip_count, 0), 2) AS pct_evening_peak,
        ROUND(100.0 * weekend_trips / NULLIF(trip_count, 0), 2) AS pct_weekend,
        
        ROUND(100.0 * male_riders / NULLIF(trip_count, 0), 2) AS pct_male,
        ROUND(100.0 * female_riders / NULLIF(trip_count, 0), 2) AS pct_female,
        
        CASE 
            WHEN trip_count > 100 AND pct_subscriber > 70 THEN 'Commuters Route'
            WHEN trip_count > 50 AND pct_customer > 60 THEN 'Tourist/Leisure Route'
            WHEN pct_weekend > 60 THEN 'Weekend Route'
            WHEN pct_morning_peak > 40 OR pct_evening_peak > 40 THEN 'Commute Corridor'
            ELSE 'General Purpose Route'
        END AS route_profile
        
    FROM route_intelligence ri
),

station_info AS (
    SELECT 
        station_id,
        station_name,
        performance_tier
    FROM {{ ref('dim_stations') }}
    WHERE station_id IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY station_id 
        ORDER BY last_activity_date DESC
    ) = 1
)

SELECT
    ra.route_id,
    ra.start_station_id,
    s1.station_name AS start_station_name,
    s1.performance_tier AS start_station_tier,
    ra.end_station_id,
    s2.station_name AS end_station_name,
    s2.performance_tier AS end_station_tier,
    
    ra.trip_count,
    ra.unique_bikes_used,
    
    RANK() OVER (ORDER BY ra.trip_count DESC) AS overall_rank,
    RANK() OVER (PARTITION BY ra.start_station_id ORDER BY ra.trip_count DESC) AS rank_from_start_station,
    RANK() OVER (PARTITION BY ra.end_station_id ORDER BY ra.trip_count DESC) AS rank_to_end_station,
    
    ra.route_volume_tier,
    ra.route_maturity,
    ra.route_profile,
    
    ra.morning_peak_trips,
    ra.evening_peak_trips,
    ra.weekend_trips,
    ra.pct_morning_peak,
    ra.pct_evening_peak,
    ra.pct_weekend,
    
    ra.subscriber_trips,
    ra.customer_trips,
    ra.pct_subscriber,
    ra.pct_customer,
    ra.male_riders,
    ra.female_riders,
    ra.pct_male,
    ra.pct_female,
    
    ra.active_years,
    ra.active_months,
    ra.first_trip_date,
    ra.last_trip_date,
    
    CASE 
        WHEN ra.last_trip_date < CURRENT_DATE() - 180 THEN 'Dormant (>6 months)'
        WHEN ra.last_trip_date < CURRENT_DATE() - 90 THEN 'Declining (3-6 months)'
        WHEN ra.trip_count < 10 AND ra.active_months >= 3 THEN 'Low Volume'
        WHEN ra.trip_count >= 50 AND ra.last_trip_date >= CURRENT_DATE() - 7 THEN 'High Performing'
        ELSE 'Stable'
    END AS route_health_status,
    
    CASE 
        WHEN ra.trip_count > 1000 THEN 'Strategic Network Route'
        WHEN ra.trip_count > 500 THEN 'Important Corridor'
        WHEN ra.trip_count > 100 THEN 'Key Connection'
        WHEN ra.trip_count > 50 THEN 'Local Route'
        ELSE 'Minor Connection'
    END AS network_significance,
    
    CASE 
        WHEN ra.pct_morning_peak > 60 THEN 'Increase morning bike availability'
        WHEN ra.pct_evening_peak > 60 THEN 'Increase evening bike availability'
        WHEN ra.unique_bikes_used < 5 AND ra.trip_count > 100 THEN 'Consider adding more bikes'
        WHEN ra.last_trip_date < CURRENT_DATE() - 90 THEN 'Review route viability'
        ELSE 'No action needed'
    END AS operational_recommendation,
    
    ROUND(
        (ra.trip_count * 0.0005) + 
        (ra.active_months * 2) + 
        (ra.unique_bikes_used * 0.5) + 
        (CASE WHEN ra.last_trip_date >= CURRENT_DATE() - 30 THEN 20 ELSE 0 END) + 
        (CASE WHEN ra.pct_subscriber > 70 THEN 10 ELSE 0 END),
        0
    ) AS route_efficiency_score,
    
    CURRENT_TIMESTAMP() AS analysis_timestamp

FROM route_analytics ra
LEFT JOIN station_info s1 ON ra.start_station_id = s1.station_id
LEFT JOIN station_info s2 ON ra.end_station_id = s2.station_id

WHERE ra.trip_count >= 1

ORDER BY 
    ra.trip_count DESC,
    ra.last_trip_date DESC