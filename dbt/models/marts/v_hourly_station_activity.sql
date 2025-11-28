-- models/marts/gold/v_hourly_station_activity.sql
{{ config(materialized='view', tags=['gold','kpi','v_hourly_station_activity']) }}

with trips as (
    select
        start_station_id,
        end_station_id,
        starttime,
        stoptime,
        usertype
    from {{ ref('fct_trips') }}
    where starttime is not null
      and stoptime is not null
),

-- YAHAN CHANGE: Station IDs ko trim karo taki dim_stations se match ho
departures as (
    select
        trim(start_station_id) as station_id,  -- TRIM ADDED HERE
        date_trunc('hour', starttime) as hour_ts,
        extract(year from starttime) as year,
        extract(month from starttime) as month,
        extract(day from starttime) as day,
        extract(hour from starttime) as hour_of_day,
        count(*) as departures_count,
        count(case when usertype = 'Subscriber' then 1 end) as subscriber_departures,
        count(case when usertype = 'Customer' then 1 end) as customer_departures
    from trips
    where start_station_id is not null
    group by trim(start_station_id), date_trunc('hour', starttime), 
             extract(year from starttime), extract(month from starttime), 
             extract(day from starttime), extract(hour from starttime)
),

arrivals as (
    select
        trim(end_station_id) as station_id,  -- TRIM ADDED HERE
        date_trunc('hour', stoptime) as hour_ts,
        extract(year from stoptime) as year,
        extract(month from stoptime) as month,
        extract(day from stoptime) as day,
        extract(hour from stoptime) as hour_of_day,
        count(*) as arrivals_count,
        count(case when usertype = 'Subscriber' then 1 end) as subscriber_arrivals,
        count(case when usertype = 'Customer' then 1 end) as customer_arrivals
    from trips
    where end_station_id is not null
    group by trim(end_station_id), date_trunc('hour', stoptime),
             extract(year from stoptime), extract(month from stoptime),
             extract(day from stoptime), extract(hour from stoptime)
),

hourly_metrics as (
    select
        coalesce(d.station_id, a.station_id) as station_id,
        coalesce(d.hour_ts, a.hour_ts) as hour_ts,
        coalesce(d.year, a.year) as year,
        coalesce(d.month, a.month) as month,
        coalesce(d.day, a.day) as day,
        coalesce(d.hour_of_day, a.hour_of_day) as hour_of_day,
        coalesce(d.departures_count, 0) as departures,
        coalesce(a.arrivals_count, 0) as arrivals,
        coalesce(d.departures_count, 0) - coalesce(a.arrivals_count, 0) as net_flow,
        
        coalesce(d.subscriber_departures, 0) as subscriber_departures,
        coalesce(d.customer_departures, 0) as customer_departures,
        coalesce(a.subscriber_arrivals, 0) as subscriber_arrivals,
        coalesce(a.customer_arrivals, 0) as customer_arrivals,
        
        coalesce(d.departures_count, 0) + coalesce(a.arrivals_count, 0) as total_activity,
        case 
            when (coalesce(d.departures_count, 0) + coalesce(a.arrivals_count, 0)) > 30 then 'Very High Activity'
            when (coalesce(d.departures_count, 0) + coalesce(a.arrivals_count, 0)) > 20 then 'High Activity'
            when (coalesce(d.departures_count, 0) + coalesce(a.arrivals_count, 0)) > 10 then 'Medium Activity'
            else 'Low Activity'
        end as activity_level,
        
        case 
            when coalesce(d.departures_count, 0) - coalesce(a.arrivals_count, 0) > 10 then 'CRITICAL: Bike Shortage Risk'
            when coalesce(d.departures_count, 0) - coalesce(a.arrivals_count, 0) < -10 then 'CRITICAL: Overflow Risk'
            when abs(coalesce(d.departures_count, 0) - coalesce(a.arrivals_count, 0)) > 5 then 'WARNING: Imbalance Detected'
            else 'Balanced Operation'
        end as operational_status

    from departures d
    full outer join arrivals a
        on d.station_id = a.station_id and d.hour_ts = a.hour_ts
)

select
    hm.station_id,
    s.station_name,
    
    hm.hour_ts as activity_hour_ts,
    hm.year,
    hm.month,
    hm.day,
    hm.hour_of_day,
    
    hm.departures,
    hm.arrivals,
    hm.net_flow,
    hm.total_activity,
    hm.activity_level,
    
    hm.subscriber_departures,
    hm.customer_departures,
    hm.subscriber_arrivals,
    hm.customer_arrivals,
    
    hm.operational_status,
    
    -- YAHAN CHANGE: New column names from updated dim_stations
    s.performance_tier,
    s.total_trip_activities as station_total_observations,  -- COLUMN NAME UPDATED
    
    rank() over(partition by hm.hour_of_day order by hm.total_activity desc) as hourly_rank,
    
    case 
        when hm.operational_status like 'CRITICAL%' and hm.hour_of_day between 7 and 9 then 'IMMEDIATE ACTION NEEDED'
        when hm.operational_status like 'WARNING%' and hm.hour_of_day between 17 and 19 then 'MONITOR CLOSELY'
        else 'STABLE OPERATION'
    end as business_alert_level

from hourly_metrics hm
left join {{ ref('dim_stations') }} s on hm.station_id = s.station_id
where hm.station_id is not null
order by hm.total_activity desc, hm.hour_ts desc