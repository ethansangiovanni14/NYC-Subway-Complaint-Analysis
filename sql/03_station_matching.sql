-- Test basic NYPD-to-MTA station-name matching.

SELECT COUNT(DISTINCT STATION_NAME)
FROM nypd_complaints
INNER JOIN (
    SELECT DISTINCT
        station_complex_id,
        station_complex
    FROM mta_ridership_clean
) AS mta
ON UPPER(
    TRIM(
        SUBSTR(
            mta.station_complex,
            1,
            INSTR(mta.station_complex, '(') - 1
        )
    )
) = STATION_NAME;

-- Result: 23 of 366 NYPD station names matched.


-- Test station-name matching after applying the final text-cleaning rules.

SELECT COUNT(DISTINCT STATION_NAME)
FROM nypd_complaints
JOIN (
    SELECT DISTINCT
        station_complex,
        station_complex_id,

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
        END AS cleaned_name

    FROM (
        SELECT DISTINCT
            station_complex,
            station_complex_id,

            CASE
                WHEN SUBSTR(
                    UPPER(
                        TRIM(
                            SUBSTR(
                                station_complex,
                                1,
                                INSTR(station_complex, '(') - 1
                            )
                        )
                    ),
                    -3,
                    3
                ) = ' ST'

                THEN SUBSTR(
                    UPPER(
                        TRIM(
                            SUBSTR(
                                station_complex,
                                1,
                                INSTR(station_complex, '(') - 1
                            )
                        )
                    ),
                    1,
                    LENGTH(
                        UPPER(
                            TRIM(
                                SUBSTR(
                                    station_complex,
                                    1,
                                    INSTR(station_complex, '(') - 1
                                )
                            )
                        )
                    ) - 3
                ) || ' STREET'

                ELSE REPLACE(
                    UPPER(
                        TRIM(
                            SUBSTR(
                                station_complex,
                                1,
                                INSTR(station_complex, '(') - 1
                            )
                        )
                    ),
                    ' ST-',
                    ' STREET-'
                )
            END AS st_cleaned_name

        FROM mta_ridership_clean
    ) AS st_cleaned
) AS mta

ON mta.cleaned_name = REPLACE(
    REPLACE(
        REPLACE(
            CASE
                WHEN SUBSTR(STATION_NAME, 1, 3) = 'ST.'
                    THEN STATION_NAME
                ELSE REPLACE(
                    STATION_NAME,
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
);

-- Result: 227 of 366 NYPD station names matched.
-- Text normalization improved matching but did not resolve all station names.


-- Group NYPD complaints into station-coordinate clusters.
-- Coordinates are rounded to account for small differences in precision.

SELECT
    STATION_NAME,
    ROUND(latitude, 5) AS rounded_latitude,
    ROUND(longitude, 5) AS rounded_longitude,
    COUNT(*) AS complaint_count
FROM nypd_complaints
GROUP BY
    STATION_NAME,
    rounded_latitude,
    rounded_longitude
ORDER BY complaint_count DESC;

-- Result:
-- Rounding grouped coordinates recorded at slightly different precision.
-- Some NYPD station names still represented multiple physical locations.


-- Match each NYPD station-coordinate cluster to its nearest MTA station.
-- ROW_NUMBER ranks candidate stations by coordinate difference.
-- Haversine distance provides an interpretable distance in miles.

SELECT *
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                STATION_NAME,
                rounded_latitude,
                rounded_longitude
            ORDER BY coordinate_difference
        ) AS match_rank

    FROM (
        SELECT
            mta.station_complex,
            mta.station_complex_id,
            mta.latitude,
            mta.longitude,

            nypd.STATION_NAME,
            nypd.rounded_latitude,
            nypd.rounded_longitude,
            nypd.complaint_count,

            ((nypd.rounded_latitude - mta.latitude)
                * (nypd.rounded_latitude - mta.latitude))
            +
            ((nypd.rounded_longitude - mta.longitude)
                * (nypd.rounded_longitude - mta.longitude))
                AS coordinate_difference,

            3959 * 2 * ASIN(
                SQRT(
                    POWER(
                        SIN(
                            RADIANS(
                                mta.latitude - nypd.rounded_latitude
                            ) / 2
                        ),
                        2
                    )
                    +
                    COS(RADIANS(nypd.rounded_latitude))
                    * COS(RADIANS(mta.latitude))
                    * POWER(
                        SIN(
                            RADIANS(
                                mta.longitude - nypd.rounded_longitude
                            ) / 2
                        ),
                        2
                    )
                )
            ) AS distance_miles

        FROM (
            SELECT DISTINCT
                station_complex,
                station_complex_id,
                latitude,
                longitude
            FROM mta_ridership_clean
        ) AS mta

        CROSS JOIN (
            SELECT
                STATION_NAME,
                ROUND(latitude, 5) AS rounded_latitude,
                ROUND(longitude, 5) AS rounded_longitude,
                COUNT(*) AS complaint_count
            FROM nypd_complaints
            GROUP BY
                STATION_NAME,
                rounded_latitude,
                rounded_longitude
        ) AS nypd
    ) AS comparisons
) AS ranked_matches

WHERE match_rank = 1
ORDER BY coordinate_difference DESC;

-- Result:
-- Each NYPD station-coordinate cluster received a nearest MTA candidate.
-- The nearest station was not always a valid match, so distance required validation.

-- Summarize how far NYPD coordinate clusters are from their nearest MTA station.

SELECT
    CASE
        WHEN distance_miles <= 0.05 THEN '0-0.05 miles'
        WHEN distance_miles <= 0.10 THEN '0.05-0.10 miles'
        WHEN distance_miles <= 0.25 THEN '0.10-0.25 miles'
        WHEN distance_miles <= 0.50 THEN '0.25-0.50 miles'
        ELSE 'Over 0.50 miles'
    END AS distance_range,

    COUNT(*) AS coordinate_clusters,
    SUM(complaint_count) AS complaints

FROM (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY
                    STATION_NAME,
                    rounded_latitude,
                    rounded_longitude
                ORDER BY coordinate_difference
            ) AS match_rank

        FROM (
            SELECT
                mta.station_complex,
                mta.station_complex_id,
                mta.latitude,
                mta.longitude,

                nypd.STATION_NAME,
                nypd.rounded_latitude,
                nypd.rounded_longitude,
                nypd.complaint_count,

                ((nypd.rounded_latitude - mta.latitude)
                    * (nypd.rounded_latitude - mta.latitude))
                +
                ((nypd.rounded_longitude - mta.longitude)
                    * (nypd.rounded_longitude - mta.longitude))
                    AS coordinate_difference,

                3959 * 2 * ASIN(
                    SQRT(
                        POWER(
                            SIN(
                                RADIANS(
                                    mta.latitude - nypd.rounded_latitude
                                ) / 2
                            ),
                            2
                        )
                        +
                        COS(RADIANS(nypd.rounded_latitude))
                        * COS(RADIANS(mta.latitude))
                        * POWER(
                            SIN(
                                RADIANS(
                                    mta.longitude - nypd.rounded_longitude
                                ) / 2
                            ),
                            2
                        )
                    )
                ) AS distance_miles

            FROM (
                SELECT DISTINCT
                    station_complex,
                    station_complex_id,
                    latitude,
                    longitude
                FROM mta_ridership_clean
            ) AS mta

            CROSS JOIN (
                SELECT
                    STATION_NAME,
                    ROUND(latitude, 5) AS rounded_latitude,
                    ROUND(longitude, 5) AS rounded_longitude,
                    COUNT(*) AS complaint_count
                FROM nypd_complaints
                GROUP BY
                    STATION_NAME,
                    rounded_latitude,
                    rounded_longitude
            ) AS nypd
        ) AS comparisons
    ) AS ranked_matches

    WHERE match_rank = 1
) AS nearest_matches

GROUP BY distance_range

ORDER BY
    CASE distance_range
        WHEN '0-0.05 miles' THEN 1
        WHEN '0.05-0.10 miles' THEN 2
        WHEN '0.10-0.25 miles' THEN 3
        WHEN '0.25-0.50 miles' THEN 4
        WHEN 'Over 0.50 miles' THEN 5
    END;

-- Result:
-- 911 coordinate clusters representing all 33,691 complaints.
-- 29,858 complaints (88.6%) were within 0.10 miles.
-- 33,497 complaints (99.4%) were within 0.25 miles.
-- 194 complaints (0.6%) were associated with clusters more than 0.25 miles away.


-- Compare cleaned NYPD and MTA names for each nearest-station match.

SELECT
    name_match,
    COUNT(*) AS coordinate_clusters,
    SUM(complaint_count) AS complaints

FROM (
    SELECT
        *,
        CASE
            WHEN nypd_cleaned_name = mta_cleaned_name
                THEN 'EXACT MATCH'
            ELSE 'NO EXACT MATCH'
        END AS name_match

    FROM (
        SELECT *
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        STATION_NAME,
                        rounded_latitude,
                        rounded_longitude
                    ORDER BY coordinate_difference
                ) AS match_rank

            FROM (
                SELECT
                    mta.station_complex,
                    mta.station_complex_id,
                    mta.latitude,
                    mta.longitude,
                    mta.mta_cleaned_name,

                    nypd.STATION_NAME,

                    REPLACE(
                        REPLACE(
                            REPLACE(
                                CASE
                                    WHEN SUBSTR(STATION_NAME, 1, 3) = 'ST.'
                                        THEN STATION_NAME
                                    ELSE REPLACE(
                                        STATION_NAME,
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
                    ) AS nypd_cleaned_name,

                    nypd.rounded_latitude,
                    nypd.rounded_longitude,
                    nypd.complaint_count,

                    ((nypd.rounded_latitude - mta.latitude)
                        * (nypd.rounded_latitude - mta.latitude))
                    +
                    ((nypd.rounded_longitude - mta.longitude)
                        * (nypd.rounded_longitude - mta.longitude))
                        AS coordinate_difference,

                    3959 * 2 * ASIN(
                        SQRT(
                            POWER(
                                SIN(
                                    RADIANS(
                                        mta.latitude - nypd.rounded_latitude
                                    ) / 2
                                ),
                                2
                            )
                            +
                            COS(RADIANS(nypd.rounded_latitude))
                            * COS(RADIANS(mta.latitude))
                            * POWER(
                                SIN(
                                    RADIANS(
                                        mta.longitude - nypd.rounded_longitude
                                    ) / 2
                                ),
                                2
                            )
                        )
                    ) AS distance_miles

                FROM (
                    SELECT DISTINCT
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

                    FROM (
                        SELECT DISTINCT
                            station_complex,
                            station_complex_id,
                            latitude,
                            longitude,

                            CASE
                                WHEN SUBSTR(
                                    UPPER(
                                        TRIM(
                                            SUBSTR(
                                                station_complex,
                                                1,
                                                INSTR(station_complex, '(') - 1
                                            )
                                        )
                                    ),
                                    -3,
                                    3
                                ) = ' ST'

                                THEN SUBSTR(
                                    UPPER(
                                        TRIM(
                                            SUBSTR(
                                                station_complex,
                                                1,
                                                INSTR(station_complex, '(') - 1
                                            )
                                        )
                                    ),
                                    1,
                                    LENGTH(
                                        UPPER(
                                            TRIM(
                                                SUBSTR(
                                                    station_complex,
                                                    1,
                                                    INSTR(station_complex, '(') - 1
                                                )
                                            )
                                        )
                                    ) - 3
                                ) || ' STREET'

                                ELSE REPLACE(
                                    UPPER(
                                        TRIM(
                                            SUBSTR(
                                                station_complex,
                                                1,
                                                INSTR(station_complex, '(') - 1
                                            )
                                        )
                                    ),
                                    ' ST-',
                                    ' STREET-'
                                )
                            END AS st_cleaned_name

                        FROM mta_ridership_clean
                    ) AS st_cleaned
                ) AS mta

                CROSS JOIN (
                    SELECT
                        STATION_NAME,
                        ROUND(latitude, 5) AS rounded_latitude,
                        ROUND(longitude, 5) AS rounded_longitude,
                        COUNT(*) AS complaint_count

                    FROM nypd_complaints

                    GROUP BY
                        STATION_NAME,
                        rounded_latitude,
                        rounded_longitude
                ) AS nypd
            ) AS comparisons
        ) AS ranked_matches

        WHERE match_rank = 1
    ) AS nearest_matches
) AS flagged_matches

GROUP BY name_match;

-- Result:
-- EXACT MATCH: 383 clusters / 16,980 complaints
-- NO EXACT MATCH: 528 clusters / 16,711 complaints
-- Non-exact matches required additional validation.