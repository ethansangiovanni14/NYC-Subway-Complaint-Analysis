-- Build the final NYPD-to-MTA station crosswalk.

DROP TABLE IF EXISTS final_station_crosswalk;

CREATE TABLE final_station_crosswalk (
    station_name TEXT,
    rounded_latitude REAL,
    rounded_longitude REAL,
    complaint_count INTEGER,
    station_complex TEXT,
    station_complex_id INTEGER,
    match_status TEXT
);


-- Create one nearest MTA candidate for each NYPD station-coordinate cluster.

DROP TABLE IF EXISTS nearest_station_candidates;

CREATE TEMP TABLE nearest_station_candidates AS

WITH nypd_clusters AS (
    SELECT
        station_name,
        ROUND(latitude, 5) AS rounded_latitude,
        ROUND(longitude, 5) AS rounded_longitude,
        COUNT(*) AS complaint_count

    FROM nypd_complaints

    GROUP BY
        station_name,
        rounded_latitude,
        rounded_longitude
),

cleaned_nypd AS (
    SELECT
        station_name,
        rounded_latitude,
        rounded_longitude,
        complaint_count,

        REPLACE(
            REPLACE(
                REPLACE(
                    CASE
                        WHEN SUBSTR(station_name, 1, 3) = 'ST.'
                            THEN station_name
                        ELSE REPLACE(
                            station_name,
                            'ST.',
                            'STREET'
                        )
                    END,
                    'AVE.',
                    'AVENUE'
                ),
                'BLVD.',
                'BLVD'
            ),
            'PKWY.',
            'PKWY'
        ) AS nypd_cleaned_name

    FROM nypd_clusters
),

mta_raw AS (
    SELECT DISTINCT
        station_complex,
        station_complex_id,
        latitude,
        longitude,

        UPPER(
            TRIM(
                SUBSTR(
                    station_complex,
                    1,
                    INSTR(station_complex, '(') - 1
                )
            )
        ) AS raw_mta_name

    FROM mta_ridership_clean
),

mta_street_cleaned AS (
    SELECT
        station_complex,
        station_complex_id,
        latitude,
        longitude,

        CASE
            WHEN SUBSTR(raw_mta_name, -3, 3) = ' ST'
                THEN SUBSTR(
                    raw_mta_name,
                    1,
                    LENGTH(raw_mta_name) - 3
                ) || ' STREET'

            ELSE REPLACE(
                raw_mta_name,
                ' ST-',
                ' STREET-'
            )
        END AS st_cleaned_name

    FROM mta_raw
),

mta_stations AS (
    SELECT
        station_complex,
        station_complex_id,
        latitude,
        longitude,

        CASE
            WHEN SUBSTR(st_cleaned_name, -3, 3) = ' AV'
                THEN SUBSTR(
                    st_cleaned_name,
                    1,
                    LENGTH(st_cleaned_name) - 3
                ) || ' AVENUE'

            ELSE REPLACE(
                REPLACE(
                    st_cleaned_name,
                    ' AV-',
                    ' AVENUE-'
                ),
                ' AV/',
                ' AVENUE/'
            )
        END AS mta_cleaned_name

    FROM mta_street_cleaned
),

ranked_matches AS (
    SELECT
        nypd.station_name,
        nypd.rounded_latitude,
        nypd.rounded_longitude,
        nypd.complaint_count,
        nypd.nypd_cleaned_name,

        mta.station_complex,
        mta.station_complex_id,
        mta.mta_cleaned_name,

        ROW_NUMBER() OVER (
            PARTITION BY
                nypd.station_name,
                nypd.rounded_latitude,
                nypd.rounded_longitude

            ORDER BY
                ((nypd.rounded_latitude - mta.latitude)
                    * (nypd.rounded_latitude - mta.latitude))
                +
                ((nypd.rounded_longitude - mta.longitude)
                    * (nypd.rounded_longitude - mta.longitude))
        ) AS match_rank

    FROM cleaned_nypd AS nypd

    CROSS JOIN mta_stations AS mta
)

SELECT
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    nypd_cleaned_name,
    station_complex,
    station_complex_id,
    mta_cleaned_name

FROM ranked_matches

WHERE match_rank = 1;


-- Check that all NYPD station-coordinate clusters are represented.

SELECT
    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints
FROM nearest_station_candidates;

-- Expected:
-- 911 clusters / 33,691 complaints



-- Insert exact cleaned-name matches.

INSERT INTO final_station_crosswalk (
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    match_status
)

SELECT
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    'EXACT_NAME'

FROM nearest_station_candidates

WHERE nypd_cleaned_name = mta_cleaned_name;


SELECT
    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints
FROM final_station_crosswalk
WHERE match_status = 'EXACT_NAME';

-- Expected:
-- 383 clusters / 16,980 complaints



-- Insert manually reviewed and accepted matches.

INSERT INTO final_station_crosswalk (
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    match_status
)

SELECT
    review.station_name,
    review.rounded_latitude,
    review.rounded_longitude,
    review.complaint_count,
    review.candidate_station_complex,
    review.station_complex_id,
    'MANUAL_ACCEPT'

FROM station_match_review AS review

WHERE review.review_status = 'ACCEPT'

    AND NOT EXISTS (
        SELECT 1
        FROM final_station_crosswalk AS final
        WHERE final.station_name = review.station_name
            AND final.rounded_latitude = review.rounded_latitude
            AND final.rounded_longitude = review.rounded_longitude
    );


SELECT
    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints
FROM final_station_crosswalk
WHERE match_status = 'MANUAL_ACCEPT';

-- Expected:
-- 174 clusters / 15,783 complaints



-- Insert low-volume matches whose NYPD station name
-- has one previously validated MTA station complex.

WITH validated_names AS (
    SELECT
        station_name,
        MIN(station_complex_id) AS validated_complex_id,
        COUNT(DISTINCT station_complex_id) AS validated_complex_count

    FROM station_match_review

    WHERE review_status = 'ACCEPT'

    GROUP BY station_name
),

mta_lookup AS (
    SELECT
        station_complex_id,
        MIN(station_complex) AS station_complex

    FROM mta_ridership_clean

    GROUP BY station_complex_id
)

INSERT INTO final_station_crosswalk (
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    match_status
)

SELECT
    candidate.station_name,
    candidate.rounded_latitude,
    candidate.rounded_longitude,
    candidate.complaint_count,
    mta.station_complex,
    validated.validated_complex_id,
    'AUTO_ACCEPT_VALIDATED_NAME'

FROM nearest_station_candidates AS candidate

JOIN validated_names AS validated
    ON candidate.station_name = validated.station_name

JOIN mta_lookup AS mta
    ON validated.validated_complex_id = mta.station_complex_id

WHERE validated.validated_complex_count = 1

    AND candidate.complaint_count < 20

    AND candidate.nypd_cleaned_name != candidate.mta_cleaned_name

    AND candidate.station_name NOT LIKE 'DISTRICT % OFFICE'

    AND NOT EXISTS (
        SELECT 1
        FROM final_station_crosswalk AS final
        WHERE final.station_name = candidate.station_name
            AND final.rounded_latitude = candidate.rounded_latitude
            AND final.rounded_longitude = candidate.rounded_longitude
    );


SELECT
    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints
FROM final_station_crosswalk
WHERE match_status = 'AUTO_ACCEPT_VALIDATED_NAME';

-- Expected:
-- 204 clusters / 546 complaints



-- Add all remaining ambiguous, administrative, and unresolved clusters.

WITH validated_names AS (
    SELECT
        station_name,
        COUNT(DISTINCT station_complex_id) AS validated_complex_count

    FROM station_match_review

    WHERE review_status = 'ACCEPT'

    GROUP BY station_name
)

INSERT INTO final_station_crosswalk (
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    match_status
)

SELECT
    candidate.station_name,
    candidate.rounded_latitude,
    candidate.rounded_longitude,
    candidate.complaint_count,
    NULL,
    NULL,

    CASE
        WHEN candidate.station_name LIKE 'DISTRICT % OFFICE'
            THEN 'ADMIN_LOCATION'

        WHEN validated.validated_complex_count > 1
            THEN 'AMBIGUOUS'

        ELSE 'UNRESOLVED'
    END

FROM nearest_station_candidates AS candidate

LEFT JOIN validated_names AS validated
    ON candidate.station_name = validated.station_name

WHERE NOT EXISTS (
    SELECT 1
    FROM final_station_crosswalk AS final
    WHERE final.station_name = candidate.station_name
        AND final.rounded_latitude = candidate.rounded_latitude
        AND final.rounded_longitude = candidate.rounded_longitude
);


-- Final expected match distribution:
-- EXACT_NAME: 383 clusters / 16,980 complaints
-- MANUAL_ACCEPT: 174 / 15,783
-- AUTO_ACCEPT_VALIDATED_NAME: 204 / 546
-- UNRESOLVED: 114 / 209
-- AMBIGUOUS: 27 / 119
-- ADMIN_LOCATION: 9 / 54
-- Total: 911 clusters / 33,691 complaints
-- 33,309 complaints (98.9%) received a validated MTA station mapping.


-- Check final crosswalk totals by match status.

SELECT
    match_status,
    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints
FROM final_station_crosswalk
GROUP BY match_status
ORDER BY complaints DESC;


-- Confirm that the crosswalk represents every NYPD cluster.

SELECT
    COUNT(*) AS total_clusters,
    SUM(complaint_count) AS total_complaints
FROM final_station_crosswalk;


-- Check that no NYPD station-coordinate cluster appears more than once.

SELECT
    station_name,
    rounded_latitude,
    rounded_longitude,
    COUNT(*) AS row_count

FROM final_station_crosswalk

GROUP BY
    station_name,
    rounded_latitude,
    rounded_longitude

HAVING COUNT(*) > 1;