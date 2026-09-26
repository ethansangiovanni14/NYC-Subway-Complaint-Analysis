-- Validate the imported Census income data.

-- Count imported Census rows.
SELECT COUNT(*) AS rows
FROM census_income;


-- Check for the extra Census description row.
SELECT *
FROM census_income
WHERE GEO_ID = 'Geography';


-- Remove the Census description row.
DELETE FROM census_income
WHERE GEO_ID = 'Geography';


-- Confirm the Census row count after cleaning.
SELECT COUNT(*) AS rows
FROM census_income;



-- Validate the station-income table.
-- station_income was created using the Python/GeoPandas
-- station-to-Census-tract spatial join and then imported into SQLite.

SELECT COUNT(*) AS rows
FROM station_income;



-- Attach Census income to the final station crosswalk.

DROP TABLE IF EXISTS station_crosswalk_with_income;

CREATE TABLE station_crosswalk_with_income AS

SELECT
    crosswalk.station_name,
    crosswalk.rounded_latitude,
    crosswalk.rounded_longitude,
    crosswalk.complaint_count,
    crosswalk.station_complex,
    crosswalk.station_complex_id,
    crosswalk.match_status,
    income.GEOID,
    income.median_household_income,
    income.income_topcoded

FROM final_station_crosswalk AS crosswalk

LEFT JOIN station_income AS income
    ON crosswalk.station_complex_id = income.station_complex_id;


-- Confirm that all station-coordinate clusters are still represented.

SELECT
    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints
FROM station_crosswalk_with_income;

-- Expected:
-- 911 clusters / 33,691 complaints


-- Check how much complaint data has usable Census income.

SELECT
    CASE
        WHEN median_household_income IS NOT NULL
            THEN 'HAS_INCOME'
        ELSE 'MISSING_INCOME'
    END AS income_status,

    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints

FROM station_crosswalk_with_income

GROUP BY income_status;

-- Result:
-- HAS_INCOME: 728 clusters / 32,414 complaints
-- MISSING_INCOME: 183 clusters / 1,277 complaints
-- 96.2% of complaints have usable median household income data.