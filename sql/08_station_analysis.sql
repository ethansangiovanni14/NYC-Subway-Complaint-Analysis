-- Create the station-level analysis table.

DROP TABLE IF EXISTS station_analysis;

CREATE TABLE station_analysis AS

WITH crime_by_station AS (
    SELECT
        station_complex_id,
        SUM(complaint_count) AS total_complaints

    FROM station_crosswalk_with_income

    WHERE station_complex_id IS NOT NULL

    GROUP BY station_complex_id
),

ridership_by_station AS (
    SELECT
        station_complex_id,
        station_complex,
        SUM(cleaned_ridership) AS total_ridership

    FROM mta_ridership_clean

    GROUP BY
        station_complex_id,
        station_complex
),

income_by_station AS (
    SELECT
        station_complex_id,
        MAX(median_household_income) AS median_household_income

    FROM station_income

    GROUP BY station_complex_id
)

SELECT
    ridership_by_station.station_complex_id,
    ridership_by_station.station_complex,
    COALESCE(crime_by_station.total_complaints, 0) AS total_complaints,
    ridership_by_station.total_ridership,
    income_by_station.median_household_income,

    (
        COALESCE(crime_by_station.total_complaints, 0) * 100000.0
    ) / ridership_by_station.total_ridership
        AS complaints_per_100k_riders

FROM ridership_by_station

LEFT JOIN crime_by_station
    ON ridership_by_station.station_complex_id =
       crime_by_station.station_complex_id

LEFT JOIN income_by_station
    ON ridership_by_station.station_complex_id =
       income_by_station.station_complex_id;


-- Confirm the number of stations.

SELECT COUNT(*) AS stations
FROM station_analysis;

-- Expected: 424 stations.



-- Show the stations with the highest complaint rates.

SELECT
    station_complex,
    total_complaints,
    total_ridership,
    complaints_per_100k_riders

FROM station_analysis

ORDER BY complaints_per_100k_riders DESC

LIMIT 10;

-- Result:
-- Broad Channel had the highest complaint rate at 41.84 per 100,000 riders,
-- followed by Coney Island-Stillwell at 38.37 and Broadway Junction at 36.46.
-- Broad Channel had only 43,016 riders, showing that very low ridership
-- can produce extreme rates.



-- Show the stations with the highest total number of complaints.

SELECT
    station_complex,
    total_complaints,
    total_ridership,
    complaints_per_100k_riders

FROM station_analysis

ORDER BY total_complaints DESC

LIMIT 10;

-- Result:
-- Times Sq-42 St/Port Authority had the most complaints with 1,443,
-- followed by Coney Island-Stillwell with 1,437 and 3 Av-149 St with 1,035.
-- Stations with the highest complaint totals did not always have
-- the highest rider-adjusted rates.



-- Check the distribution of annual station ridership.

SELECT
    MIN(total_ridership) AS minimum_ridership,
    AVG(total_ridership) AS average_ridership,
    MAX(total_ridership) AS maximum_ridership

FROM station_analysis;

-- Result:
-- Minimum annual station ridership: 43,016
-- Average annual station ridership: 3,062,538
-- Maximum annual station ridership: 48,509,290



-- Count stations by annual ridership range.

SELECT
    CASE
        WHEN total_ridership < 100000 THEN 'Under 100k'
        WHEN total_ridership < 500000 THEN '100k-500k'
        WHEN total_ridership < 1000000 THEN '500k-1M'
        WHEN total_ridership < 5000000 THEN '1M-5M'
        ELSE '5M+'
    END AS ridership_range,

    COUNT(*) AS stations

FROM station_analysis

GROUP BY ridership_range

ORDER BY MIN(total_ridership);

-- Result:
-- Under 100k: 4 stations
-- 100k-500k: 21 stations
-- 500k-1M: 84 stations
-- 1M-5M: 253 stations
-- 5M+: 62 stations
-- A 500,000-rider minimum excludes only 25 of 424 stations
-- and reduces unstable rates from very low-ridership stations.



-- Show the highest complaint rates among stations
-- with at least 500,000 annual riders.

SELECT
    station_complex,
    total_complaints,
    total_ridership,
    complaints_per_100k_riders

FROM station_analysis

WHERE total_ridership >= 500000

ORDER BY complaints_per_100k_riders DESC

LIMIT 10;

-- Result:
-- Coney Island-Stillwell had the highest complaint rate
-- at 38.37 per 100,000 riders.
-- Broadway Junction ranked second at 36.46,
-- followed by Ralph Av at 27.10.
-- The ranking differs substantially from the raw complaint ranking.



-- Create a table for ridership and complaint volume correlation analysis.

DROP TABLE IF EXISTS ridership_complaint_correlation;

CREATE TABLE ridership_complaint_correlation AS

SELECT
    station_complex,
    total_ridership,
    total_complaints

FROM station_analysis;



-- Create a table for ridership and complaint rate correlation analysis.

DROP TABLE IF EXISTS ridership_complaint_rate_analysis;

CREATE TABLE ridership_complaint_rate_analysis AS

SELECT
    station_complex,
    total_ridership,
    complaints_per_100k_riders

FROM station_analysis

WHERE total_ridership >= 500000;


-- Check the number of stations included in the complaint-rate analysis.

SELECT COUNT(*) AS stations
FROM ridership_complaint_rate_analysis;



-- Create a table for median household income
-- and complaint-rate correlation analysis.

DROP TABLE IF EXISTS income_complaint_rate_analysis;

CREATE TABLE income_complaint_rate_analysis AS

SELECT
    station_complex,
    median_household_income,
    total_ridership,
    complaints_per_100k_riders

FROM station_analysis

WHERE median_household_income IS NOT NULL
    AND total_ridership >= 500000;



-- Compare complaint rates across neighborhood income groups.

SELECT
    CASE
        WHEN median_household_income < 50000 THEN 'Under $50k'
        WHEN median_household_income < 75000 THEN '$50k-$75k'
        WHEN median_household_income < 100000 THEN '$75k-$100k'
        WHEN median_household_income < 150000 THEN '$100k-$150k'
        ELSE '$150k+'
    END AS income_group,

    COUNT(*) AS stations,
    AVG(complaints_per_100k_riders) AS average_complaint_rate

FROM income_complaint_rate_analysis

GROUP BY income_group

ORDER BY MIN(median_household_income);