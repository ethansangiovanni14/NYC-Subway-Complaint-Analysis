-- Create station-level data for Tableau.

DROP TABLE IF EXISTS tableau_station_summary;

CREATE TABLE tableau_station_summary AS

SELECT
    station_complex_id,
    station_complex,
    total_complaints,
    total_ridership,
    median_household_income,
    complaints_per_100k_riders,

    CASE
        WHEN median_household_income < 50000
            THEN 'Under $50k'

        WHEN median_household_income < 75000
            THEN '$50k-$75k'

        WHEN median_household_income < 100000
            THEN '$75k-$100k'

        WHEN median_household_income < 150000
            THEN '$100k-$150k'

        WHEN median_household_income IS NOT NULL
            THEN '$150k+'

        ELSE 'Missing'
    END AS income_group

FROM station_analysis;



-- Create station-by-time data for Tableau.

DROP TABLE IF EXISTS tableau_station_time;

CREATE TABLE tableau_station_time AS

SELECT
    station_complex_id,
    station_complex,
    time_period,
    total_complaints,
    total_ridership,
    median_household_income,
    complaints_per_100k_riders,

    CASE
        WHEN total_ridership >= 100000
            THEN 'Include'

        ELSE 'Low Ridership'
    END AS ridership_threshold

FROM station_time_analysis;



-- Create systemwide time-of-day data for Tableau.

DROP TABLE IF EXISTS tableau_time_summary;

CREATE TABLE tableau_time_summary AS

WITH nypd_time AS (
    SELECT
        CMPLNT_FR_DT,
        CMPLNT_FR_TM,

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
    complaints.time_period,
    complaints.total_complaints,
    ridership.total_ridership,

    (
        complaints.total_complaints * 100000.0
    ) / ridership.total_ridership
        AS complaints_per_100k_riders

FROM complaints_by_period AS complaints

JOIN ridership_by_period AS ridership
    ON complaints.time_period = ridership.time_period;
	