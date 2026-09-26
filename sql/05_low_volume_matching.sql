-- Analyze and resolve lower-volume non-exact station matches.
-- Low-volume clusters contain fewer than 20 complaints.


-- Show the distance distribution for all low-volume non-exact matches.

SELECT
    CASE
        WHEN distance_miles <= 0.05 THEN '0-0.05'
        WHEN distance_miles <= 0.10 THEN '0.05-0.10'
        WHEN distance_miles <= 0.25 THEN '0.10-0.25'
        WHEN distance_miles <= 0.50 THEN '0.25-0.50'
        ELSE 'Over 0.50'
    END AS distance_range,

    COUNT(*) AS coordinate_clusters,
    SUM(complaint_count) AS complaints

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
    AND mta_cleaned_name != nypd_cleaned_name
    AND complaint_count < 20

GROUP BY distance_range;

-- Result:
-- 402 clusters / 1,375 complaints total.
-- 0-0.05 miles: 114 clusters / 627 complaints
-- 0.05-0.10 miles: 102 / 308
-- 0.10-0.25 miles: 115 / 305
-- 0.25-0.50 miles: 55 / 102
-- Over 0.50 miles: 16 / 33



-- Reuse station-name mappings that were already manually validated.
-- A station name is automatically reusable only when it was validated
-- to exactly one MTA station_complex_id.

WITH validated_names AS (
    SELECT
        station_name,
        MIN(station_complex_id) AS validated_complex_id,
        COUNT(DISTINCT station_complex_id) AS validated_complex_count

    FROM station_match_review

    WHERE review_status = 'ACCEPT'

    GROUP BY station_name
),

nearest_low_volume AS (
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
    ) AS ranked

    WHERE match_rank = 1
        AND mta_cleaned_name != nypd_cleaned_name
        AND complaint_count < 20
),

categorized_matches AS (
    SELECT
        low.*,

        CASE
            WHEN low.STATION_NAME LIKE 'DISTRICT % OFFICE'
                THEN 'ADMIN_LOCATION'

            WHEN validated.validated_complex_count = 1
                THEN 'AUTO_ACCEPT_VALIDATED_NAME'

            WHEN validated.validated_complex_count > 1
                THEN 'AMBIGUOUS_VALIDATED_NAME'

            ELSE 'NEEDS_REVIEW'
        END AS match_status

    FROM nearest_low_volume AS low

    LEFT JOIN validated_names AS validated
        ON low.STATION_NAME = validated.station_name
)

SELECT
    match_status,
    COUNT(*) AS coordinate_clusters,
    SUM(complaint_count) AS complaints

FROM categorized_matches

GROUP BY match_status

ORDER BY coordinate_clusters DESC;

-- Result before additional low-volume manual review:
-- NEEDS_REVIEW: 194 clusters / 794 complaints
-- AUTO_ACCEPT_VALIDATED_NAME: 180 clusters / 479 complaints
-- AMBIGUOUS_VALIDATED_NAME: 19 clusters / 48 complaints
-- ADMIN_LOCATION: 9 clusters / 54 complaints

-- Check Transit District for close-distance matches
-- where station identity required additional validation.

SELECT
    STATION_NAME,
    ROUND(latitude, 5) AS rounded_latitude,
    ROUND(longitude, 5) AS rounded_longitude,
    TRANSIT_DISTRICT,
    COUNT(*) AS complaints

FROM nypd_complaints

WHERE
    (
        STATION_NAME = '46 STREET'
        AND ROUND(latitude, 5) = 40.74316
        AND ROUND(longitude, 5) = -73.9187
    )

    OR (
        STATION_NAME = 'BAY PARKWAY'
        AND ROUND(latitude, 5) = 40.60195
        AND ROUND(longitude, 5) = -73.99381
    )

    OR (
        STATION_NAME = 'BAY PARKWAY'
        AND ROUND(latitude, 5) = 40.62091
        AND ROUND(longitude, 5) = -73.9753
    )

    OR (
        STATION_NAME = '5 AVENUE'
        AND ROUND(latitude, 5) = 40.76042
        AND ROUND(longitude, 5) = -73.97583
    )

    OR (
        STATION_NAME = '5 AVENUE'
        AND ROUND(latitude, 5) = 40.76428
        AND ROUND(longitude, 5) = -73.97302
    )

    OR (
        STATION_NAME = '86TH STREET'
        AND ROUND(latitude, 5) = 40.77787
        AND ROUND(longitude, 5) = -73.95174
    )

    OR (
        STATION_NAME = '72ND STREET'
        AND ROUND(latitude, 5) = 40.7688
        AND ROUND(longitude, 5) = -73.95836
    )

    OR (
        STATION_NAME = 'MYRTLE AVENUE'
        AND ROUND(latitude, 5) = 40.69943
        AND ROUND(longitude, 5) = -73.91231
    )

GROUP BY
    STATION_NAME,
    rounded_latitude,
    rounded_longitude,
    TRANSIT_DISTRICT

ORDER BY
    STATION_NAME,
    rounded_latitude;

-- Manual review result:
-- 57 NEEDS_REVIEW clusters / 416 complaints were examined
-- in the <= 0.05-mile group.
-- 37 clusters / 392 complaints had clear station matches.
-- 20 clusters / 24 complaints were not accepted based on distance alone.



-- Save accepted matches from the <= 0.05-mile manual review.

WITH accepted (
    STATION_NAME,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    distance_miles
) AS (

    VALUES
        ('46 STREET', 40.74316, -73.9187, 19, '46 St-Bliss St (7)', 458, 0.0140408556198111),
        ('AVENUE "U"', 40.59894, -73.95548, 19, 'Avenue U (Q)', 52, 0.03429516407342),
        ('BAY PARKWAY', 40.60195, -73.99381, 19, 'Bay Pkwy (D)', 68, 0.00666866645264838),
        ('5 AVENUE', 40.76042, -73.97583, 18, '5 Av/53 St (E,F)', 276, 0.0359744172643659),
        ('EAST TREMONT AV.-WESTCHESTER S', 40.84017, -73.84261, 18, 'Westchester Sq-E Tremont Av (6)', 363, 0.0261196813804613),
        ('NEW UTRECHT AVENUE', 40.62606, -73.99702, 18, '62 St/New Utrecht Av (D,N)', 615, 0.0346062845015468),
        ('238 ST.-NEREID AVE.', 40.89845, -73.8543, 17, 'Nereid Av (2,5)', 417, 0.00639165279645854),
        ('242 ST.-VAN CORTLANDT PARK', 40.88946, -73.89827, 17, 'Van Cortlandt Park-242 St (1)', 293, 0.0218358201235311),
        ('AVENUE "X"', 40.59011, -73.97419, 17, 'Avenue X (F)', 252, 0.0340038759855192),
        ('AVENUE "J"', 40.62528, -73.96047, 16, 'Avenue J (Q)', 49, 0.0239692758029183),
        ('9TH STREET', 40.67036, -73.98871, 15, '4 Av-9 St (F,G,R)', 608, 0.0223021108927093),
        ('BOTANIC GARDEN', 40.67066, -73.95797, 15, 'Franklin Av-Medgar Evers College/Botanic Garden (2,3,4,5,S)', 626, 0.0390772151371421),
        ('DYRE AVE.-EASTCHESTER', 40.88782, -73.83101, 15, 'Eastchester-Dyre Av (5)', 442, 0.0344738974332062),
        ('40 STREET', 40.74381, -73.92426, 14, '40 St-Lowery St (7)', 459, 0.0127122805629641),
        ('5 AVENUE', 40.76428, -73.97302, 14, '5 Av/59 St (N,R,W)', 8, 0.0406147398701083),
        ('BEDFORD PK. BLVD.-LEHMAN COLLE', 40.87338, -73.88937, 14, 'Bedford Park Blvd-Lehman College (4)', 380, 0.0361236071929293),
        ('86TH STREET', 40.77787, -73.95174, 13, '86 St (Q)', 476, 0.00295876355087121),
        ('72ND STREET', 40.7688, -73.95836, 11, '72 St (Q)', 477, 0.00366317759535043),
        ('AVENUE "P"', 40.60881, -73.973, 11, 'Avenue P (F)', 249, 0.009318325176937),
        ('63 DRIVE-REGO PARK', 40.73012, -73.86231, 10, '63 Dr-Rego Park (M,R)', 263, 0.0416887284077078),
        ('ASTOR PLACE', 40.72986, -73.99143, 9, 'Astor Pl (6)', 407, 0.0230905775828273),
        ('AVENUE "M"', 40.61811, -73.95911, 8, 'Avenue M (Q)', 50, 0.0371175054684322),
        ('BEVERLEY ROAD', 40.64441, -73.96409, 8, 'Beverley Rd (Q)', 45, 0.033604225113825),
        ('62 STREET', 40.62606, -73.99702, 7, '62 St/New Utrecht Av (D,N)', 615, 0.0346062845015468),
        ('75 ST.-ELDERTS LANE', 40.69118, -73.86806, 7, '75 St-Elderts Ln (J,Z)', 85, 0.0491892864743271),
        ('AVENUE "I"', 40.62598, -73.97623, 7, 'Avenue I (F)', 246, 0.0459049589301531),
        ('39 AVENUE', 40.75269, -73.93291, 6, '39 Av-Dutch Kills (N,W)', 6, 0.0154332059727806),
        ('MIDDLETOWN ROAD', 40.84346, -73.83682, 6, 'Middletown Rd (6)', 362, 0.0382408715888385),
        ('FRESH POND ROAD', 40.70577, -73.89657, 5, 'Fresh Pond Rd (M)', 109, 0.046340360753237),
        ('81 ST.-MUSEUM OF NATURAL HISTO', 40.78202, -73.97172, 4, '81 St-Museum of Natural History (C,B)', 159, 0.0462557427324996),
        ('NECK ROAD', 40.59503, -73.95473, 4, 'Neck Rd (Q)', 53, 0.0270130067221301),
        ('BAY PARKWAY', 40.62091, -73.9753, 3, 'Bay Pkwy (F)', 247, 0.00983664500863964),
        ('225 ST.-MARBLE HILL', 40.87464, -73.90974, 2, 'Marble Hill-225 St (1)', 296, 0.00725728652721089),
        ('ASTOR PLACE', 40.72988, -73.99072, 2, 'Astor Pl (6)', 407, 0.0218805646161627),
        ('DYRE AVE.-EASTCHESTER', 40.88781, -73.83129, 2, 'Eastchester-Dyre Av (5)', 442, 0.0415180361267514),
        ('45 ROAD-COURT HOUSE SQUARE', 40.74692, -73.94532, 1, 'Court Sq-23 St (7,E,F,G)', 606, 0.0216308216115673),
        ('MYRTLE AVENUE', 40.69943, -73.91231, 1, 'Myrtle-Wyckoff Avs (M,L)', 630, 0.0214209252144778)
)

INSERT INTO station_match_review (
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    candidate_station_complex,
    station_complex_id,
    distance_miles,
    review_status,
    review_reason
)

SELECT
    STATION_NAME,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    distance_miles,
    'ACCEPT',
    'Validated low-volume match using station name, distance, and Transit District where needed'

FROM accepted;

-- Save clear matches from the 0.05-0.10-mile review.

WITH accepted (
    STATION_NAME,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    distance_miles
) AS (

    VALUES
        ('WEST 8 STREET-NY AQUARIUM', 40.5753, -73.97659, 18, 'W 8 St-NY Aquarium (F,Q)', 57, 0.0664926040030672),
        ('207 ST.-INWOOD', 40.86769, -73.92121, 17, 'Inwood-207 St (A)', 143, 0.0733891122397671),
        ('CORTLANDT STREET', 40.71278, -74.01168, 9, 'WTC Cortlandt (1)', 328, 0.0706134666055252),
        ('AVENUE "H"', 40.63006, -73.96137, 8, 'Avenue H (Q)', 48, 0.0563934949127733),
        ('AQUEDUCT-NORTH CONDUIT AVE.', 40.66712, -73.83465, 6, 'Aqueduct-N Conduit Av (A)', 197, 0.0830818161080892),
        ('CORTELYOU ROAD', 40.64161, -73.96356, 6, 'Cortelyou Rd (Q)', 46, 0.0503303013804363),
        ('AVENUE "N"', 40.61403, -73.97399, 3, 'Avenue N (F)', 248, 0.0774852396206226),
        ('138 ST.-GRAND CONCOURSE', 40.81035, -73.92494, 2, '3 Av-138 St (6)', 377, 0.0633401736531832),
        ('AQUEDUCT-RACETRACK', 40.6708, -73.83595, 2, 'Aqueduct Racetrack (A)', 196, 0.089564270980227),
        ('CORTLANDT STREET', 40.71102, -74.0108, 2, 'WTC Cortlandt (1)', 328, 0.091999058532108),
        ('PARK PLACE', 40.67417, -73.9567, 2, 'Park Pl (S)', 141, 0.0639851691064216),
        ('CORTLANDT STREET', 40.71153, -74.01046, 1, 'Chambers St/WTC/Park Place/Cortlandt St (2,3,A,C,E,R,W)', 624, 0.088256245429885)
)

INSERT INTO station_match_review (
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    candidate_station_complex,
    station_complex_id,
    distance_miles,
    review_status,
    review_reason
)

SELECT
    STATION_NAME,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    distance_miles,
    'ACCEPT',
    'Clear station-name match from 0.05-0.10 mile review'

FROM accepted;


-- Confirm the second review added the expected matches.

SELECT
    COUNT(*) AS clusters,
    SUM(complaint_count) AS complaints
FROM station_match_review
WHERE review_reason =
    'Clear station-name match from 0.05-0.10 mile review';

-- Result: 12 clusters / 76 complaints.


-- Check overall manually accepted station-matching coverage.

SELECT
    COUNT(*) AS accepted_rows,
    SUM(complaint_count) AS accepted_complaints
FROM station_match_review
WHERE review_status = 'ACCEPT';

-- Expected result after low-volume review:
-- 174 accepted clusters / 15,783 complaints.


-- Check for duplicate accepted mappings.

SELECT
    station_name,
    rounded_latitude,
    rounded_longitude,
    COUNT(*) AS duplicate_count

FROM station_match_review

WHERE review_status = 'ACCEPT'

GROUP BY
    station_name,
    rounded_latitude,
    rounded_longitude

HAVING COUNT(*) > 1

ORDER BY duplicate_count DESC;

-- Expected result: 0 rows.