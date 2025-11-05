<img src="https://atrium.ai/wp-content/uploads/2021/05/Atrium_FullColor_Horizontal.svg" alt="drawing" width="100"/>

# Urban Mobility Snowflake Data Engineering Release Notes 
Prepared by Atrium.ai   _Palak.Tailor@atrium.ai_ 


# Release Notes

## Release 2025.11.04 - Stage model for Citi Bike trips (DLJ25-204)

**Status**  Planned Deployment 2025-11-06

[**PR4**](https://github.com/rohitanandatrium/Urban_Mobility_Demo_Luminates_2025/pull/PR4)

## 🚀 New Implementation

### 1. [DLJ25-204 – Stage Model for Citi Bike Trips](https://atriumai.atlassian.net/browse/DLJ25-204)

Created a dbt staging model to structure and clean raw Citi Bike JSON data for downstream models.

**Implementation Details:**
- Implemented in `models/staging/stg_citibike_trips.sql` as a view using the dbt `source()` function to extract key fields (`trip_id`, `started_at`, `ended_at`, station details, etc.) from the raw `VARIANT` column.
- Added YAML file for tests and schema configuration.

---

### 2. [DLJ25-204 – Added Schema Tests for Staging Model](https://atriumai.atlassian.net/browse/DLJ25-204)

Added schema and data tests for staging models.

**Implementation Details:**
- Defined `stg_citibike_trips.yml` with `not_null` and `unique` tests for `trip_id`, `starttime`, and field-level documentation.



