-- Identify and fix the MTA ridership data type issue.

-- Check total 2025 ridership by station complex.
-- The initial rankings appeared incorrect, with major stations
-- showing unexpectedly low annual ridership totals.
SELECT
    SUM(sum_ridership) AS total_ridership,
    station_complex_id,
    station_complex
FROM mta_ridership
GROUP BY station_complex_id, station_complex
ORDER BY total_ridership DESC;

-- Result:
-- The rankings appeared incorrect.
-- Major stations such as Times Sq-42 St had unexpectedly low totals.


-- Check how many ridership values were imported as text.
SELECT COUNT(*)
FROM mta_ridership
WHERE TYPEOF(sum_ridership) = 'text';

-- Result: 280,616 ridership values were stored as text.
-- Values containing thousands separators, such as "1,008",
-- were not being interpreted correctly by SUM().


-- Test converting text ridership values into integers.
SELECT
    sum_ridership,
    CAST(REPLACE(sum_ridership, ',', '') AS INTEGER) AS cleaned_ridership
FROM mta_ridership
WHERE TYPEOF(sum_ridership) = 'text'
LIMIT 20;

-- Result:
-- Values containing commas were successfully converted to integers.


-- Create a cleaned MTA ridership table.
-- Remove commas and convert all ridership values to integers
-- while preserving the original imported table.
DROP TABLE IF EXISTS mta_ridership_clean;

CREATE TABLE mta_ridership_clean AS
SELECT
    transit_timestamp,
    station_complex_id,
    station_complex,
    borough,
    latitude,
    longitude,
    CAST(REPLACE(sum_ridership, ',', '') AS INTEGER) AS cleaned_ridership
FROM mta_ridership;


-- Confirm that no rows were lost.
SELECT COUNT(*)
FROM mta_ridership_clean;

-- Result: 3,628,476 rows.


-- Confirm cleaned ridership values are stored as integers.
SELECT DISTINCT TYPEOF(cleaned_ridership)
FROM mta_ridership_clean;

-- Result: integer


-- Check the cleaned table for NULL values.
SELECT
    COUNT(*) - COUNT(station_complex_id) AS null_station_id,
    COUNT(*) - COUNT(station_complex) AS null_station_name,
    COUNT(*) - COUNT(borough) AS null_borough,
    COUNT(*) - COUNT(latitude) AS null_latitude,
    COUNT(*) - COUNT(longitude) AS null_longitude,
    COUNT(*) - COUNT(transit_timestamp) AS null_timestamp,
    COUNT(*) - COUNT(cleaned_ridership) AS null_ridership
FROM mta_ridership_clean;

-- Result:
-- 0 NULL values were found in the important columns.


-- Recheck total 2025 ridership by station complex using cleaned values.
SELECT
    SUM(cleaned_ridership) AS total_ridership,
    station_complex_id,
    station_complex
FROM mta_ridership_clean
GROUP BY station_complex_id, station_complex
ORDER BY total_ridership DESC;

-- Result:
-- Times Sq-42 St/Port Authority: 48,509,290 riders
-- Grand Central-42 St: 36,363,366
-- 34 St-Herald Sq: 26,485,099
-- The corrected rankings confirm that the original issue was caused
-- by comma-containing ridership values being stored as text.