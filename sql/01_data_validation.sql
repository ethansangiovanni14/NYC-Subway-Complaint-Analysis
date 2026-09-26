-- Validate the imported NYPD complaint data.

-- Count imported NYPD rows.
SELECT COUNT(*)
FROM nypd_complaints;


-- Check premises types.
SELECT DISTINCT PREM_TYP_DESC
FROM nypd_complaints;


-- Check complaint date range.
SELECT MIN(CMPLNT_FR_DT), MAX(CMPLNT_FR_DT)
FROM nypd_complaints;


-- Check for complaints with missing station names.
SELECT COUNT(*)
FROM nypd_complaints
WHERE STATION_NAME IS NULL;


-- Count distinct NYPD station names.
SELECT COUNT(DISTINCT STATION_NAME) AS STATION_NAMES_TOTAL
FROM nypd_complaints;

-- Result: 366



-- Validate the imported MTA ridership data.

-- Count imported MTA rows.
SELECT COUNT(*)
FROM mta_ridership;

-- Result: 3,628,476 rows


-- Check the stored timestamp range.
SELECT MIN(transit_timestamp), MAX(transit_timestamp)
FROM mta_ridership;

-- transit_timestamp is stored as text, so MIN/MAX compares text values
-- rather than identifying the true chronological minimum and maximum.


-- Confirm how transit_timestamp values are stored.
SELECT TYPEOF(transit_timestamp)
FROM mta_ridership;

-- Result: transit_timestamp values are stored as text.


-- Count unique MTA station complexes.
SELECT COUNT(DISTINCT station_complex_id)
FROM mta_ridership;

-- Result: 424 unique station complexes.


-- Check whether each station_complex_id maps to one station_complex.
SELECT
    COUNT(DISTINCT station_complex),
    station_complex_id
FROM mta_ridership
GROUP BY station_complex_id
HAVING COUNT(DISTINCT station_complex) > 1;

-- Result: 0 rows.
-- Each station_complex_id is associated with one station_complex.


-- Check whether station complex IDs have multiple coordinates.
SELECT
    station_complex_id,
    COUNT(DISTINCT latitude),
    COUNT(DISTINCT longitude)
FROM mta_ridership
GROUP BY station_complex_id;

-- Result: Every station_complex_id has one distinct latitude and longitude.


-- Check for duplicate station_complex_id and timestamp combinations.
SELECT
    COUNT(*) AS num_rows,
    station_complex_id,
    transit_timestamp
FROM mta_ridership
GROUP BY station_complex_id, transit_timestamp
HAVING COUNT(*) > 1;

-- Result: 0 rows.
-- Each station complex has one row per timestamp.


-- Check for station complexes with fewer than 8,760 hourly records.
SELECT
    station_complex_id,
    COUNT(transit_timestamp) AS hourly_timestamps
FROM mta_ridership
GROUP BY station_complex_id
HAVING COUNT(transit_timestamp) < 8760;


-- Check the range of hourly coverage across station complexes.
SELECT
    MIN(hourly_timestamps),
    MAX(hourly_timestamps)
FROM (
    SELECT COUNT(transit_timestamp) AS hourly_timestamps
    FROM mta_ridership
    GROUP BY station_complex_id
);

-- Result:
-- Minimum hourly records: 4,946
-- Maximum hourly records: 8,760


-- Check important MTA columns for NULL values.
SELECT
    COUNT(*) - COUNT(station_complex_id) AS null_station_id,
    COUNT(*) - COUNT(station_complex) AS null_station_name,
    COUNT(*) - COUNT(borough) AS null_borough,
    COUNT(*) - COUNT(latitude) AS null_latitude,
    COUNT(*) - COUNT(longitude) AS null_longitude,
    COUNT(*) - COUNT(transit_timestamp) AS null_timestamp,
    COUNT(*) - COUNT(sum_ridership) AS null_ridership
FROM mta_ridership;

-- Result: 0 NULL values were found in the important MTA columns.