<img src="https://atrium.ai/wp-content/uploads/2021/05/Atrium_FullColor_Horizontal.svg" alt="drawing" width="100"/>

# Urban Mobility Snowflake Data Engineering Release Notes 
Prepared by Atrium.ai   Palak.Tailor@atrium.ai  , Himanshu.Gautam@atrium.ai ,  Ishan@atrium.ai 


# Release Notes

## Release 2025.11.3 - Final KPI Views for Citi Bike Analytics (DLJ25-274)

**Status**  Planned Deployment 2025-11-14 [**PR6**](https://github.com/rohitanandatrium/Urban_Mobility_Demo_Luminates_2025/pull/6)

##  New Implementation

### [DLJ25-274 – Final KPI Views for Citi Bike Analytics](https://atriumai.atlassian.net/browse/DLJ25-274)

1. Built a comprehensive set of KPI views in the Gold layer to support Citi Bike's operational and strategic insights.
  
    - Created five analytical views under `models/marts/gold/`:
        - **`V_HOURLY_STATION_ACTIVITY`** - Tracks departures, arrivals, and net flow per hour for bike redistribution.
        - **`V_POPULAR_ROUTES`** - Analyzes trip patterns, counts, and user type breakdown for route planning.
        - **`V_USER_TYPE_ANALYSIS`** - Provides insights into subscriber vs. casual rider behavior.
        - **`V_BIKE_UTILIZATION`** - Monitors fleet utilization and identifies underused/faulty bikes.
        - **`V_TRIP_DURATION_ANALYSIS`** - Analyzes trip length patterns and rider behavior by duration buckets.
    - All views built on top of existing fact (`FCT_TRIPS`) and dimension (`DIM_STATIONS`) models.
    - Implemented proper aggregations, calculations, and followed project naming standards.
    - Added comprehensive documentation for KPI definitions and business purposes.

## Release 2025.11.2- Marts model for Citi Bike trips (DLJ25-233)
 
**Status**  Planned Deployment 2025-11-08 [**PR5**](https://github.com/rohitanandatrium/Urban_Mobility_Demo_Luminates_2025/pull/5)

##  New Implementation

### [DLJ25-205 – Gold Layer Model for Citi Bike Data Marts](https://atriumai.atlassian.net/browse/DLJ25-233)

1. Implemented the **Gold layer analytical models** for Citi Bike — DIM_STATIONS and FCT_TRIPS — built on top of the staging model stg_citibike_trips.

    - Added two dbt models under models/marts/:
      - **dim_stations.sql** — provides a unique, clean list of all bike stations with their geospatial metadata.  
      - **fct_trips.sql** — serves as the trip-level fact model with temporal and usage metrics for analytics.
    - Both models follow **dbt best practices**, use **CTEs** for clarity, and are **materialized as tables**.
    - Added **YAML configuration** files (dim_stations.yml and fct_trips.yml) including:
      - unique and not_null tests for key columns.
      - Field-level documentation for better lineage tracking.
    - All models were validated using dbt build and passed tests successfully.


## Release 2025.11.1 - Stage model for Citi Bike trips (DLJ25-204)

**Status**  Deployed 2025-11-06 [**PR4**](https://github.com/rohitanandatrium/Urban_Mobility_Demo_Luminates_2025/pull/PR4)
##  New Implementation

### [DLJ25-204 – Stage Model for Citi Bike Trips](https://atriumai.atlassian.net/browse/DLJ25-204)

1. Created a dbt staging model to structure and clean raw Citi Bike JSON data for downstream models.

    - Implemented in models/staging/stg_citibike_trips.sql as a view using the dbt source() function to extract key fields (trip_id, started_at, ended_at, station details, etc.) from the raw VARIANT column.
    - Added YAML file for tests and schema configuration.

2. Added schema and data tests for staging models.

    - Defined stg_citibike_trips.yml with not_null and unique tests for trip_id, starttime, and field-level documentation.


