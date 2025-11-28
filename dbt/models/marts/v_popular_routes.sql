-- models/marts/gold/v_popular_routes.sql
{{ config(materialized='view', tags=['gold','kpi','v_popular_routes']) }}

with trips as (
  select
    start_station_id,
    end_station_id,
    usertype,
    starttime,
    bikeid,
    age,
    gender,
    -- Use available columns only
    case 
        when extract(hour from starttime) between 7 and 9 then 'Morning Peak'
        when extract(hour from starttime) between 17 and 19 then 'Evening Peak'
        when extract(hour from starttime) between 12 and 14 then 'Lunch Peak'
        else 'Off-Peak'
    end as peak_period,
    case 
        when extract(dow from starttime) in (0,6) then 'Weekend'
        else 'Weekday'
    end as day_type,
    extract(month from starttime) as trip_month,
    extract(year from starttime) as trip_year
  from {{ ref('fct_trips') }}
  where start_station_id is not null
    and end_station_id is not null
    and start_station_id != end_station_id
),

route_intelligence as (
  select
    start_station_id,
    end_station_id,
    
    -- Core volume metrics (GROWS with data)
    count(*) as trip_count,
    
    -- Temporal patterns (DYNAMIC)
    count(case when peak_period = 'Morning Peak' then 1 end) as morning_peak_trips,
    count(case when peak_period = 'Evening Peak' then 1 end) as evening_peak_trips,
    count(case when day_type = 'Weekend' then 1 end) as weekend_trips,
    
    -- User demographics (GROWS)
    count(case when lower(usertype) = 'subscriber' then 1 end) as subscriber_trips,
    count(case when lower(usertype) in ('customer','casual') then 1 end) as customer_trips,
    
    -- Gender distribution (DYNAMIC)
    count(case when gender = 1 then 1 end) as male_riders,
    count(case when gender = 2 then 1 end) as female_riders,
    
    -- Bike utilization (GROWS)
    count(distinct bikeid) as unique_bikes_used,
    
    -- Monthly trends (DYNAMIC - updates monthly)
    count(distinct trip_month) as active_months,
    count(distinct trip_year) as active_years,
    min(starttime) as first_trip_date,
    max(starttime) as last_trip_date,
    
    -- Route maturity (DYNAMIC classification)
    case 
        when count(distinct trip_month) >= 6 then 'Established Route'
        when count(distinct trip_month) >= 3 then 'Growing Route'
        else 'Emerging Route'
    end as route_maturity,
    
    -- Popularity tiers (DYNAMIC - updates with data)
    case 
        when count(*) > 1000 then 'Super Route'
        when count(*) > 500 then 'Major Route'
        when count(*) > 100 then 'Medium Route'
        when count(*) > 50 then 'Minor Route'
        else 'Niche Route'
    end as route_volume_tier

  from trips
  group by start_station_id, end_station_id
),

route_analytics as (
  select
    ri.*,
    
    -- Percentage calculations (DYNAMIC ratios)
    round(100.0 * subscriber_trips / nullif(trip_count, 0), 2) as pct_subscriber,
    round(100.0 * customer_trips / nullif(trip_count, 0), 2) as pct_customer,
    round(100.0 * morning_peak_trips / nullif(trip_count, 0), 2) as pct_morning_peak,
    round(100.0 * weekend_trips / nullif(trip_count, 0), 2) as pct_weekend,
    
    -- Gender percentages (DYNAMIC)
    round(100.0 * male_riders / nullif(trip_count, 0), 2) as pct_male,
    round(100.0 * female_riders / nullif(trip_count, 0), 2) as pct_female,
    
    -- Growth potential (DYNAMIC business logic)
    case 
        when trip_count > 100 and pct_subscriber > 70 then 'Commuters Route - High Potential'
        when trip_count > 50 and pct_customer > 60 then 'Tourist Route - Seasonal Potential'
        when active_months >= 6 and trip_count < 100 then 'Stable Niche - Limited Growth'
        else 'Emerging - Monitor Growth'
    end as growth_potential,
    
    -- Network ranking (DYNAMIC - updates with new routes)
    rank() over(order by trip_count desc) as overall_rank

  from route_intelligence ri
)

select
  -- Core route identity
  ra.start_station_id,
  s1.station_name as start_station_name,
  ra.end_station_id,
  s2.station_name as end_station_name,
  
  -- Volume and ranking (GROWS with data)
  ra.trip_count,
  ra.overall_rank,
  ra.route_volume_tier,
  ra.route_maturity,
  
  -- User demographics (DYNAMIC)
  ra.subscriber_trips,
  ra.customer_trips,
  ra.pct_subscriber,
  ra.pct_customer,
  ra.pct_male,
  ra.pct_female,
  
  -- Temporal patterns (DYNAMIC)
  ra.morning_peak_trips,
  ra.evening_peak_trips,
  ra.weekend_trips,
  ra.pct_morning_peak,
  ra.pct_weekend,
  
  -- Operational intelligence (GROWS)
  ra.unique_bikes_used,
  ra.active_months,
  ra.active_years,
  ra.first_trip_date,
  ra.last_trip_date,
  
  -- Strategic insights (DYNAMIC business logic)
  ra.growth_potential,
  case 
      when ra.overall_rank <= 10 then 'Strategic Network Route'
      when ra.overall_rank <= 50 then 'Important Corridor'
      else 'Supporting Route'
  end as network_significance,
  
  -- Health monitoring (DYNAMIC - updates with time)
  case 
      when ra.last_trip_date < current_date() - 90 then 'Dormant Route - Review'
      when ra.trip_count < 10 and ra.active_months >= 3 then 'Low Volume - Investigate'
      else 'Active Route'
  end as route_health_status

from route_analytics ra
left join {{ ref('dim_stations') }} s1 on ra.start_station_id = s1.station_id
left join {{ ref('dim_stations') }} s2 on ra.end_station_id = s2.station_id
where ra.trip_count >= 1
order by ra.trip_count desc