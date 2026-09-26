-- Analyze complaint volume and ridership by time of day.
-- Time periods:
-- Morning: 6:00 AM-11:59 AM
-- Afternoon: 12:00 PM-4:59 PM
-- Evening: 5:00 PM-9:59 PM
-- Late Night: 10:00 PM-5:59 AM

WITH nypd_time AS (
    SELECT
        CMPLNT_FR_DT,
        CMPLNT_FR_TM,
        CAST(SUBSTR(CMPLNT_FR_TM, 1, 2) AS INTEGER) AS complaint_hour,

        CASE
            WHEN CAST(SUBSTR(CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 6 AND 11
                THEN 'Morning'

            WHEN CAST(SUBSTR(CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 12 AND 16
                THEN 'Afternoon'

            WHEN CAST(SUBSTR(CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 17 AND 21
                THEN 'Evening'

            WHEN CAST(SUBSTR(CMPLNT_FR_TM, 1, 2) AS INTEGER) >= 22
                OR CAST(SUBSTR(CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 0 AND 5
                THEN 'Late Night'
        END AS time_period

    FROM nypd_complaints
),

complaints_by_period AS (
    SELECT
        time_period,
        COUNT(*) AS total_complaints

    FROM nypd_time

    GROUP BY time_period
),

mta_hour AS (
    SELECT
        transit_timestamp,
        cleaned_ridership,

        CASE
            WHEN SUBSTR(transit_timestamp, 12, 2) = '12'
                AND SUBSTR(transit_timestamp, 21, 2) = 'AM'
                THEN 0

            WHEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER)
                BETWEEN 1 AND 11
                AND SUBSTR(transit_timestamp, 21, 2) = 'AM'
                THEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER)

            WHEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER)
                BETWEEN 1 AND 11
                AND SUBSTR(transit_timestamp, 21, 2) = 'PM'
                THEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER) + 12

            WHEN SUBSTR(transit_timestamp, 12, 2) = '12'
                AND SUBSTR(transit_timestamp, 21, 2) = 'PM'
                THEN 12
        END AS ridership_hour

    FROM mta_ridership_clean
),

mta_time AS (
    SELECT
        ridership_hour,
        cleaned_ridership,

        CASE
            WHEN ridership_hour BETWEEN 6 AND 11
                THEN 'Morning'

            WHEN ridership_hour BETWEEN 12 AND 16
                THEN 'Afternoon'

            WHEN ridership_hour BETWEEN 17 AND 21
                THEN 'Evening'

            WHEN ridership_hour >= 22
                OR ridership_hour BETWEEN 0 AND 5
                THEN 'Late Night'
        END AS time_period

    FROM mta_hour
),

ridership_by_period AS (
    SELECT
        time_period,
        SUM(cleaned_ridership) AS total_ridership

    FROM mta_time

    GROUP BY time_period
)

SELECT
    complaints_by_period.time_period,
    complaints_by_period.total_complaints,
    ridership_by_period.total_ridership,

    (
        complaints_by_period.total_complaints * 100000.0
    ) / ridership_by_period.total_ridership
        AS complaints_per_100k_riders

FROM complaints_by_period

JOIN ridership_by_period
    ON complaints_by_period.time_period =
       ridership_by_period.time_period;



-- Create a station-by-time analysis comparing complaints and ridership.

DROP TABLE IF EXISTS station_time_analysis;

CREATE TABLE station_time_analysis AS

WITH nypd_station_time AS (
    SELECT
        crosswalk.station_complex_id,
        crosswalk.station_complex,
        complaints.CMPLNT_FR_TM,

        CASE
            WHEN CAST(SUBSTR(complaints.CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 6 AND 11
                THEN 'Morning'

            WHEN CAST(SUBSTR(complaints.CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 12 AND 16
                THEN 'Afternoon'

            WHEN CAST(SUBSTR(complaints.CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 17 AND 21
                THEN 'Evening'

            WHEN CAST(SUBSTR(complaints.CMPLNT_FR_TM, 1, 2) AS INTEGER) >= 22
                OR CAST(SUBSTR(complaints.CMPLNT_FR_TM, 1, 2) AS INTEGER)
                BETWEEN 0 AND 5
                THEN 'Late Night'
        END AS time_period

    FROM nypd_complaints AS complaints

    JOIN final_station_crosswalk AS crosswalk
        ON complaints.station_name = crosswalk.station_name
        AND ROUND(complaints.latitude, 5) = crosswalk.rounded_latitude
        AND ROUND(complaints.longitude, 5) = crosswalk.rounded_longitude

    WHERE crosswalk.station_complex_id IS NOT NULL
),

complaints_by_station_time AS (
    SELECT
        station_complex_id,
        station_complex,
        time_period,
        COUNT(*) AS total_complaints

    FROM nypd_station_time

    GROUP BY
        station_complex_id,
        station_complex,
        time_period
),

mta_hour AS (
    SELECT
        station_complex_id,
        station_complex,
        cleaned_ridership,

        CASE
            WHEN SUBSTR(transit_timestamp, 12, 2) = '12'
                AND SUBSTR(transit_timestamp, 21, 2) = 'AM'
                THEN 0

            WHEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER)
                BETWEEN 1 AND 11
                AND SUBSTR(transit_timestamp, 21, 2) = 'AM'
                THEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER)

            WHEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER)
                BETWEEN 1 AND 11
                AND SUBSTR(transit_timestamp, 21, 2) = 'PM'
                THEN CAST(SUBSTR(transit_timestamp, 12, 2) AS INTEGER) + 12

            WHEN SUBSTR(transit_timestamp, 12, 2) = '12'
                AND SUBSTR(transit_timestamp, 21, 2) = 'PM'
                THEN 12
        END AS ridership_hour

    FROM mta_ridership_clean
),

mta_station_time AS (
    SELECT
        station_complex_id,
        station_complex,
        cleaned_ridership,

        CASE
            WHEN ridership_hour BETWEEN 6 AND 11
                THEN 'Morning'

            WHEN ridership_hour BETWEEN 12 AND 16
                THEN 'Afternoon'

            WHEN ridership_hour BETWEEN 17 AND 21
                THEN 'Evening'

            WHEN ridership_hour >= 22
                OR ridership_hour BETWEEN 0 AND 5
                THEN 'Late Night'
        END AS time_period

    FROM mta_hour
),

ridership_by_station_time AS (
    SELECT
        station_complex_id,
        station_complex,
        time_period,
        SUM(cleaned_ridership) AS total_ridership

    FROM mta_station_time

    GROUP BY
        station_complex_id,
        station_complex,
        time_period
)

SELECT
    ridership.station_complex_id,
    ridership.station_complex,
    ridership.time_period,

    COALESCE(
        complaints.total_complaints,
        0
    ) AS total_complaints,

    ridership.total_ridership,
    income.median_household_income,

    (
        COALESCE(complaints.total_complaints, 0) * 100000.0
    ) / ridership.total_ridership
        AS complaints_per_100k_riders

FROM ridership_by_station_time AS ridership

LEFT JOIN complaints_by_station_time AS complaints
    ON ridership.station_complex_id = complaints.station_complex_id
    AND ridership.time_period = complaints.time_period

LEFT JOIN station_income AS income
    ON ridership.station_complex_id = income.station_complex_id;



-- Check the number of station-time rows.

SELECT COUNT(*)
FROM station_time_analysis;



-- Validate station-time complaint and ridership totals.

SELECT
    SUM(total_complaints) AS total_complaints,
    SUM(total_ridership) AS total_ridership

FROM station_time_analysis;



-- Show the highest station-by-time complaint rates
-- with at least 100,000 riders in that time period.

SELECT
    station_complex,
    time_period,
    total_complaints,
    total_ridership,
    median_household_income,
    complaints_per_100k_riders

FROM station_time_analysis

WHERE total_ridership >= 100000

ORDER BY complaints_per_100k_riders DESC

LIMIT 15;