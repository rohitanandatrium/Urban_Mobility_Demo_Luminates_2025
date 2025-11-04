Hi @Palak Tailor  

Good Afternoon!



\## Release 2025.11.04 - Stage model for Citi Bike trips (DLJ25-204)

\*\*Status:\*\* Planned Deployment – 2025-11-04  

\[\*\*PR DLJ25-204\*\*](https://github.com/rohitanandatrium/Urban\_Mobility\_Demo\_Luminates\_2025/pull/new/DLJ25-204\_PalakTailor)



---



\### Changes

1\. \*\*DLJ25-204: Stage model for Citi Bike trips\*\*  

&nbsp;  Created a dbt staging model to structure and clean raw Citi Bike JSON data for downstream models.

&nbsp;   

&nbsp;  \* \*\*Implementation Details:\*\*  

&nbsp;    Implemented in `models/staging/stg\_citibike\_trips.sql` using dbt `source()` function to extract key fields (trip\_id, started\_at, ended\_at, station details, etc.) from the raw `VARIANT` column. Added YAML file for tests and schema configuration.  

&nbsp;  \* \*\*Impact/Benefit:\*\*  

&nbsp;    Enables consistent and typed data for downstream transformations. Simplifies data analysis and ensures schema consistency.  

&nbsp;  \* \*\*Related Task:\*\*  

&nbsp;    Used in `DAILY\_CITIBIKE\_STAGING\_TASK`.



2\. \*\*DLJ25-204: Added schema tests for staging model\*\*  

&nbsp;  Added schema and data tests for staging models.  

&nbsp;  \* \*\*Implementation Details:\*\*  

&nbsp;    Defined `stg\_citibike\_trips.yml` with `not\_null` and `unique` tests for `trip\_id`, and field-level documentation.  

&nbsp;  \* \*\*Impact/Benefit:\*\*  

&nbsp;    Improves data validation and ensures integrity before further transformations.  

&nbsp;  \* \*\*Related Task:\*\*  

&nbsp;    dbt tests for staging models.



---



\### Implementation Files Changed

\- `models/staging/stg\_citibike\_trips.sql`

\- `models/staging/stg\_citibike\_trips.yml`

\- `models/staging/sources.yml`

\- `docs/2025-11-04\_Release\_DLJ25-204\_PalakTailor.md`



---



\### QA / Local Run Verification

\- ✅ `dbt debug` passed successfully.  

\- ✅ `dbt run --models stg\_citibike\_trips` executed successfully.  

\- ✅ `dbt test --models stg\_citibike\_trips` tests passed.  



---



\### Developer

👩‍💻 \*\*Palak Tailor\*\*



\### Reviewer

@rohitanandatrium



