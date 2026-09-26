-- Create a review table for manually validated station matches.

DROP TABLE IF EXISTS station_match_review;

CREATE TABLE station_match_review (
    station_name TEXT,
    rounded_latitude REAL,
    rounded_longitude REAL,
    complaint_count INTEGER,
    candidate_station_complex TEXT,
    station_complex_id INTEGER,
    distance_miles REAL,
    review_status TEXT,
    review_reason TEXT
);


-- Add high-priority non-exact matches to the review table.
-- High-priority clusters contain at least 20 complaints.

INSERT INTO station_match_review (
    station_name,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    candidate_station_complex,
    station_complex_id,
    distance_miles
)

SELECT
    STATION_NAME,
    rounded_latitude,
    rounded_longitude,
    complaint_count,
    station_complex,
    station_complex_id,
    distance_miles

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
    AND complaint_count >= 20

ORDER BY complaint_count DESC;

-- Result:
-- 126 high-priority non-exact clusters were added.
-- These represented 15,336 complaints.


-- Accept Coney Island-Stillwell.

UPDATE station_match_review
SET
    review_status = 'ACCEPT',
    review_reason = 'Same station, reversed naming'
WHERE station_name = 'STILLWELL AVENUE-CONEY ISLAND'
    AND rounded_latitude = 40.57557
    AND rounded_longitude = -73.98122;


-- Accept validated station matches.

UPDATE station_match_review
SET
    review_status = 'ACCEPT',

    review_reason = CASE
        WHEN station_name = '42 ST.-PORT AUTHORITY BUS TERM'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'FRANKLIN AVENUE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'W. 4 STREET'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'ATLANTIC AVENUE'
            THEN 'Same station/complex'

        WHEN station_name = 'BROADWAY-EAST NEW YORK'
            THEN 'Legacy/alternate station name'

        WHEN station_name = 'ROOSEVELT AVE.-JACKSON HEIGHTS'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'UTICA AVE.-CROWN HEIGHTS'
            THEN 'Same station, reversed naming'

        WHEN station_name = '42 ST.-TIMES SQUARE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'PARSONS/ARCHER-JAMAICA CENTER'
            THEN 'Same station, reordered naming'

        WHEN station_name = 'BROADWAY-EASTERN PKWY'
            THEN 'Legacy/alternate station name'

        WHEN station_name = '14 STREET'
            THEN 'Coordinate identifies 14 St-Union Sq'

        WHEN station_name = 'JAY STREET-BOROUGH HALL'
            THEN 'Legacy/alternate station name'

        WHEN station_name = 'MAIN ST.-FLUSHING'
            THEN 'Same station, reversed naming'

        WHEN station_name = 'EAST 180 STREET'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'FORDHAM ROAD'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '42 ST.-GRAND CENTRAL'
            THEN 'Same station, reversed naming'

        WHEN station_name = '34 ST.-HERALD SQ.'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'KINGSBRIDGE ROAD'
            THEN 'Same station, abbreviated naming'
    END

WHERE
    (station_name = '42 ST.-PORT AUTHORITY BUS TERM'
        AND rounded_latitude = 40.75723
        AND rounded_longitude = -73.98979)

    OR (station_name = 'FRANKLIN AVENUE'
        AND rounded_latitude = 40.67066
        AND rounded_longitude = -73.95797)

    OR (station_name = 'W. 4 STREET'
        AND rounded_latitude = 40.73171
        AND rounded_longitude = -74.00096)

    OR (station_name = 'ATLANTIC AVENUE'
        AND rounded_latitude = 40.68405
        AND rounded_longitude = -73.97746)

    OR (station_name = 'BROADWAY-EAST NEW YORK'
        AND rounded_latitude = 40.67859
        AND rounded_longitude = -73.90613)

    OR (station_name = 'ROOSEVELT AVE.-JACKSON HEIGHTS'
        AND rounded_latitude = 40.74681
        AND rounded_longitude = -73.89175)

    OR (station_name = 'UTICA AVE.-CROWN HEIGHTS'
        AND rounded_latitude = 40.6688
        AND rounded_longitude = -73.93112)

    OR (station_name = '42 ST.-TIMES SQUARE'
        AND rounded_latitude = 40.75604
        AND rounded_longitude = -73.98695)

    OR (station_name = 'PARSONS/ARCHER-JAMAICA CENTER'
        AND rounded_latitude = 40.70247
        AND rounded_longitude = -73.79992)

    OR (station_name = 'BROADWAY-EASTERN PKWY'
        AND rounded_latitude = 40.67952
        AND rounded_longitude = -73.90457)

    OR (station_name = '14 STREET'
        AND rounded_latitude = 40.73443
        AND rounded_longitude = -73.9899)

    OR (station_name = 'JAY STREET-BOROUGH HALL'
        AND rounded_latitude = 40.69223
        AND rounded_longitude = -73.9873)

    OR (station_name = 'MAIN ST.-FLUSHING'
        AND rounded_latitude = 40.75957
        AND rounded_longitude = -73.83014)

    OR (station_name = 'EAST 180 STREET'
        AND rounded_latitude = 40.84087
        AND rounded_longitude = -73.87281)

    OR (station_name = 'FORDHAM ROAD'
        AND rounded_latitude = 40.86135
        AND rounded_longitude = -73.89774)

    OR (station_name = '42 ST.-GRAND CENTRAL'
        AND rounded_latitude = 40.75144
        AND rounded_longitude = -73.97605)

    OR (station_name = '34 ST.-HERALD SQ.'
        AND rounded_latitude = 40.74979
        AND rounded_longitude = -73.98777)

    OR (station_name = 'KINGSBRIDGE ROAD'
        AND rounded_latitude = 40.86607
        AND rounded_longitude = -73.89438);


-- Flag Columbus Circle for additional review.

UPDATE station_match_review
SET
    review_status = 'INVESTIGATE',
    review_reason = 'NYPD station name conflicts with nearest MTA candidate'
WHERE station_name = '59 ST.-COLUMBUS CIRCLE'
    AND rounded_latitude = 40.76502
    AND rounded_longitude = -73.98484;


-- Accept the next reviewed station matches.

UPDATE station_match_review
SET
    review_status = 'ACCEPT',

    review_reason = CASE
        WHEN station_name = '42 STREET'
            THEN 'Coordinate identifies 42 St-Bryant Park complex'

        WHEN station_name = '71 AVE.-FOREST HILLS'
            THEN 'Same station, reversed/abbreviated naming'

        WHEN station_name = 'WYCKOFF AVENUE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = '74 ST.-BROADWAY'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'GUN HILL ROAD'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'HOYT-SCHERMERHORN'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'EAST 174 STREET'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '14 STREET'
            THEN 'Coordinate identifies 14 St complex'

        WHEN station_name = 'PACIFIC STREET'
            THEN 'Legacy/component name of same MTA complex'

        WHEN station_name = 'SUTPHIN BLVD.-ARCHER AVE.'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'UNION SQUARE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'BROADWAY/NASSAU'
            THEN 'Legacy/component name of same MTA complex'

        WHEN station_name = 'EAST 149 STREET'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'ROCKAWAY PKWY-CANARSIE'
            THEN 'Same station, reversed naming'

        WHEN station_name = 'DELANCEY STREET'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'CHAMBERS ST.-WORLD TRADE CENTE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = '47-50 STS./ROCKEFELLER CTR.'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'UNION TURNPIKE-KEW GARDENS'
            THEN 'Same station, reversed/abbreviated naming'

        WHEN station_name = '14 ST.-UNION SQUARE'
            THEN 'Same station, abbreviated naming'
    END

WHERE
    (station_name = '42 STREET'
        AND rounded_latitude = 40.75484
        AND rounded_longitude = -73.98412)

    OR (station_name = '71 AVE.-FOREST HILLS'
        AND rounded_latitude = 40.72145
        AND rounded_longitude = -73.84398)

    OR (station_name = 'WYCKOFF AVENUE'
        AND rounded_latitude = 40.69994
        AND rounded_longitude = -73.91181)

    OR (station_name = '74 ST.-BROADWAY'
        AND rounded_latitude = 40.74684
        AND rounded_longitude = -73.89143)

    OR (station_name = 'GUN HILL ROAD'
        AND rounded_latitude = 40.87739
        AND rounded_longitude = -73.86649)

    OR (station_name = 'HOYT-SCHERMERHORN'
        AND rounded_latitude = 40.68902
        AND rounded_longitude = -73.98616)

    OR (station_name = 'EAST 174 STREET'
        AND rounded_latitude = 40.83737
        AND rounded_longitude = -73.88777)

    OR (station_name = '14 STREET'
        AND rounded_latitude = 40.73975
        AND rounded_longitude = -74.00252)

    OR (station_name = 'PACIFIC STREET'
        AND rounded_latitude = 40.68376
        AND rounded_longitude = -73.97876)

    OR (station_name = 'SUTPHIN BLVD.-ARCHER AVE.'
        AND rounded_latitude = 40.70058
        AND rounded_longitude = -73.80774)

    OR (station_name = 'UNION SQUARE'
        AND rounded_latitude = 40.73521
        AND rounded_longitude = -73.99172)

    OR (station_name = 'BROADWAY/NASSAU'
        AND rounded_latitude = 40.71022
        AND rounded_longitude = -74.00774)

    OR (station_name = 'EAST 149 STREET'
        AND rounded_latitude = 40.81213
        AND rounded_longitude = -73.90418)

    OR (station_name = 'ROCKAWAY PKWY-CANARSIE'
        AND rounded_latitude = 40.64513
        AND rounded_longitude = -73.90231)

    OR (station_name = 'DELANCEY STREET'
        AND rounded_latitude = 40.71856
        AND rounded_longitude = -73.9882)

    OR (station_name = 'CHAMBERS ST.-WORLD TRADE CENTE'
        AND rounded_latitude = 40.71153
        AND rounded_longitude = -74.01046)

    OR (station_name = '47-50 STS./ROCKEFELLER CTR.'
        AND rounded_latitude = 40.75802
        AND rounded_longitude = -73.98179)

    OR (station_name = 'UNION TURNPIKE-KEW GARDENS'
        AND rounded_latitude = 40.71444
        AND rounded_longitude = -73.83126)

    OR (station_name = '14 STREET'
        AND rounded_latitude = 40.73855
        AND rounded_longitude = -73.99968)

    OR (station_name = '14 ST.-UNION SQUARE'
        AND rounded_latitude = 40.73443
        AND rounded_longitude = -73.9899);


-- Review the next group of station matches.

UPDATE station_match_review
SET
    review_status = CASE
        WHEN station_name = '42 ST.-TIMES SQUARE'
            AND rounded_latitude = 40.75353
            AND rounded_longitude = -73.99454
            THEN 'INVESTIGATE'
        ELSE 'ACCEPT'
    END,

    review_reason = CASE
        WHEN station_name = '168 ST.-WASHINGTON HTS.'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'VAN WYCK BLVD.-BRIARWOOD'
            THEN 'Legacy/alternate station name'

        WHEN station_name = '34 STREET'
            THEN 'Coordinate identifies 34 St-Herald Sq'

        WHEN station_name = '42 ST.-TIMES SQUARE'
            AND rounded_latitude = 40.75353
            AND rounded_longitude = -73.99454
            THEN 'NYPD station name conflicts with nearest MTA candidate'

        WHEN station_name = 'SMITH-9 STREETS'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'WEST 34 STREET/HUDSON YARDS'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '14 STREET'
            THEN 'Coordinate identifies 14 St/6 Av complex'

        WHEN station_name = 'BROOKLYN BRIDGE-CITY HALL'
            THEN 'Named component of same MTA complex'

        WHEN station_name = '110 ST.-CENTRAL PARK NORTH'
            THEN 'Same station, alternate naming'

        WHEN station_name = 'ROOSEVELT AVE.-JACKSON HEIGHTS'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'SOUNDVIEW AVENUE'
            THEN 'Named component of same station'

        WHEN station_name = '59 STREET'
            THEN 'Coordinate identifies Lexington Av/59 St complex'

        WHEN station_name = 'PARSONS/ARCHER-JAMAICA CENTER'
            THEN 'Same station, reordered naming'

        WHEN station_name = 'KINGSTON-THROOP AVENUES'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'BROADWAY/LAFAYETTE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'SUTTER AVENUE-RUTLAND ROAD'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'KINGS HIGHWAY'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'CHAMBERS STREET'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'KINGSBRIDGE ROAD'
            THEN 'Coordinate identifies Kingsbridge Rd 4 station'

        WHEN station_name = 'FORDHAM ROAD'
            THEN 'Coordinate identifies Fordham Rd 4 station'
    END

WHERE
    (station_name = '168 ST.-WASHINGTON HTS.'
        AND rounded_latitude = 40.84095
        AND rounded_longitude = -73.93947)

    OR (station_name = 'VAN WYCK BLVD.-BRIARWOOD'
        AND rounded_latitude = 40.71019
        AND rounded_longitude = -73.82112)

    OR (station_name = '34 STREET'
        AND rounded_latitude = 40.74829
        AND rounded_longitude = -73.98818)

    OR (station_name = '42 ST.-TIMES SQUARE'
        AND rounded_latitude = 40.75353
        AND rounded_longitude = -73.99454)

    OR (station_name = 'SMITH-9 STREETS'
        AND rounded_latitude = 40.67474
        AND rounded_longitude = -73.99777)

    OR (station_name = 'WEST 34 STREET/HUDSON YARDS'
        AND rounded_latitude = 40.75578
        AND rounded_longitude = -74.00199)

    OR (station_name = '14 STREET'
        AND rounded_latitude = 40.73736
        AND rounded_longitude = -73.99684)

    OR (station_name = 'BROOKLYN BRIDGE-CITY HALL'
        AND rounded_latitude = 40.71314
        AND rounded_longitude = -74.00406)

    OR (station_name = '110 ST.-CENTRAL PARK NORTH'
        AND rounded_latitude = 40.79883
        AND rounded_longitude = -73.95202)

    OR (station_name = 'ROOSEVELT AVE.-JACKSON HEIGHTS'
        AND rounded_latitude = 40.74684
        AND rounded_longitude = -73.89143)

    OR (station_name = 'SOUNDVIEW AVENUE'
        AND rounded_latitude = 40.8295
        AND rounded_longitude = -73.87461)

    OR (station_name = '59 STREET'
        AND rounded_latitude = 40.76223
        AND rounded_longitude = -73.96819)

    OR (station_name = 'PARSONS/ARCHER-JAMAICA CENTER'
        AND rounded_latitude = 40.70248
        AND rounded_longitude = -73.79995)

    OR (station_name = 'KINGSTON-THROOP AVENUES'
        AND rounded_latitude = 40.67994
        AND rounded_longitude = -73.94121)

    OR (station_name = 'BROADWAY/LAFAYETTE'
        AND rounded_latitude = 40.72543
        AND rounded_longitude = -73.99677)

    OR (station_name = 'SUTTER AVENUE-RUTLAND ROAD'
        AND rounded_latitude = 40.66523
        AND rounded_longitude = -73.92318)

    OR (station_name = 'KINGS HIGHWAY'
        AND rounded_latitude = 40.60913
        AND rounded_longitude = -73.9574)

    OR (station_name = 'CHAMBERS STREET'
        AND rounded_latitude = 40.71314
        AND rounded_longitude = -74.00406)

    OR (station_name = 'KINGSBRIDGE ROAD'
        AND rounded_latitude = 40.86748
        AND rounded_longitude = -73.8974)

    OR (station_name = 'FORDHAM ROAD'
        AND rounded_latitude = 40.86276
        AND rounded_longitude = -73.90108);


-- Review the next group of station matches.

UPDATE station_match_review
SET
    review_status = CASE
        WHEN station_name = 'ATLANTIC AVENUE'
            AND rounded_latitude = 40.69022
            AND rounded_longitude = -73.96028
            THEN 'INVESTIGATE'
        ELSE 'ACCEPT'
    END,

    review_reason = CASE
        WHEN station_name = 'ESSEX STREET'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'WYCKOFF AVENUE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'NEWKIRK AVENUE'
            THEN 'Same station, alternate naming'

        WHEN station_name = 'ATLANTIC AVENUE'
            THEN 'NYPD station name conflicts with nearest MTA candidate'

        WHEN station_name = '96TH STREET'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '42 ST.-TIMES SQUARE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'BLEECKER STREET'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'EAST 180 STREET'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'KOSCIUSKO STREET'
            THEN 'Same station, alternate spelling'

        WHEN station_name = '42 ST.-PORT AUTHORITY BUS TERM'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'BEDFORD-NOSTRAND AVENUES'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'BOROUGH HALL'
            THEN 'Named component of same MTA complex'

        WHEN station_name = '182-183 STREETS'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'CHRISTOPHER ST.-SHERIDAN SQ.'
            THEN 'Same station, legacy/alternate naming'

        WHEN station_name = 'EAST 177 ST.-PARKCHESTER'
            THEN 'Same station, alternate naming'

        WHEN station_name = '6 AVENUE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'BEDFORD PK. BLVD.'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'CLINTON-WASHINGTON AVENUES'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '179 ST.-JAMAICA'
            THEN 'Same station, reversed naming'

        WHEN station_name = '168 ST.-WASHINGTON HTS.'
            THEN 'Same station, abbreviated naming'
    END

WHERE
    (station_name = 'ESSEX STREET'
        AND rounded_latitude = 40.71856
        AND rounded_longitude = -73.9882)

    OR (station_name = 'WYCKOFF AVENUE'
        AND rounded_latitude = 40.69995
        AND rounded_longitude = -73.91181)

    OR (station_name = 'NEWKIRK AVENUE'
        AND rounded_latitude = 40.63999
        AND rounded_longitude = -73.94841)

    OR (station_name = 'ATLANTIC AVENUE'
        AND rounded_latitude = 40.69022
        AND rounded_longitude = -73.96028)

    OR (station_name = '96TH STREET'
        AND rounded_latitude = 40.78425
        AND rounded_longitude = -73.94709)

    OR (station_name = '42 ST.-TIMES SQUARE'
        AND rounded_latitude = 40.75581
        AND rounded_longitude = -73.9864)

    OR (station_name = 'BLEECKER STREET'
        AND rounded_latitude = 40.72593
        AND rounded_longitude = -73.99465)

    OR (station_name = 'EAST 180 STREET'
        AND rounded_latitude = 40.84087
        AND rounded_longitude = -73.87282)

    OR (station_name = 'KOSCIUSKO STREET'
        AND rounded_latitude = 40.69386
        AND rounded_longitude = -73.9297)

    OR (station_name = '42 ST.-PORT AUTHORITY BUS TERM'
        AND rounded_latitude = 40.75595
        AND rounded_longitude = -73.99073)

    OR (station_name = 'BEDFORD-NOSTRAND AVENUES'
        AND rounded_latitude = 40.68944
        AND rounded_longitude = -73.95512)

    OR (station_name = 'BOROUGH HALL'
        AND rounded_latitude = 40.69255
        AND rounded_longitude = -73.99097)

    OR (station_name = '182-183 STREETS'
        AND rounded_latitude = 40.85605
        AND rounded_longitude = -73.90078)

    OR (station_name = 'CHRISTOPHER ST.-SHERIDAN SQ.'
        AND rounded_latitude = 40.73363
        AND rounded_longitude = -74.00279)

    OR (station_name = 'EAST 177 ST.-PARKCHESTER'
        AND rounded_latitude = 40.833
        AND rounded_longitude = -73.86154)

    OR (station_name = '6 AVENUE'
        AND rounded_latitude = 40.73736
        AND rounded_longitude = -73.99684)

    OR (station_name = 'BEDFORD PK. BLVD.'
        AND rounded_latitude = 40.87211
        AND rounded_longitude = -73.88785)

    OR (station_name = 'CLINTON-WASHINGTON AVENUES'
        AND rounded_latitude = 40.68304
        AND rounded_longitude = -73.96478)

    OR (station_name = '179 ST.-JAMAICA'
        AND rounded_latitude = 40.713
        AND rounded_longitude = -73.78237)

    OR (station_name = '168 ST.-WASHINGTON HTS.'
        AND rounded_latitude = 40.84108
        AND rounded_longitude = -73.93977);


-- Review the next group of station matches.

UPDATE station_match_review
SET
    review_status = CASE
        WHEN station_name = '42 ST.-GRAND CENTRAL'
            AND rounded_latitude = 40.75353
            AND rounded_longitude = -73.99454
            THEN 'INVESTIGATE'
        ELSE 'ACCEPT'
    END,

    review_reason = CASE
        WHEN station_name = '95 STREET-BAY RIDGE'
            THEN 'Same station, reversed naming'

        WHEN station_name = 'MYRTLE/WYCKOFF AVENUES'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'LEFFERTS BLVD.'
            THEN 'Named component of same station'

        WHEN station_name = 'LEXINGTON AVE.'
            THEN 'Coordinate identifies Lexington Av/63 St'

        WHEN station_name = '51 STREET'
            THEN 'Named component of same MTA complex'

        WHEN station_name = '57 STREET'
            THEN 'Named component of same station'

        WHEN station_name = 'SOUTH FERRY'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'LORIMER STREET'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'EAST TREMONT AVE.-WEST FARMS S'
            THEN 'Same station, reordered naming'

        WHEN station_name = 'GRAND AVE.-NEWTON'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'WILLETS POINT-SHEA STADIUM'
            THEN 'Legacy station name'

        WHEN station_name = '42 ST.-GRAND CENTRAL'
            AND rounded_latitude = 40.75353
            AND rounded_longitude = -73.99454
            THEN 'NYPD station name conflicts with nearest MTA candidate'

        WHEN station_name = '82 ST.-JACKSON HEIGHTS'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'BEVERLY ROAD'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'DITMARS BLVD.-ASTORIA'
            THEN 'Same station, reversed naming'

        WHEN station_name = '42 ST.-TIMES SQUARE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'COURT SQUARE'
            THEN 'Same station/complex'

        WHEN station_name = 'METROPOLITAN AVENUE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'PRESIDENT STREET'
            THEN 'Same station, alternate naming'

        WHEN station_name = '174-175 STREETS'
            THEN 'Same station, abbreviated naming'
    END

WHERE
    (station_name = '95 STREET-BAY RIDGE'
        AND rounded_latitude = 40.61599
        AND rounded_longitude = -74.03113)

    OR (station_name = 'MYRTLE/WYCKOFF AVENUES'
        AND rounded_latitude = 40.69953
        AND rounded_longitude = -73.91104)

    OR (station_name = 'LEFFERTS BLVD.'
        AND rounded_latitude = 40.68623
        AND rounded_longitude = -73.82417)

    OR (station_name = 'LEXINGTON AVE.'
        AND rounded_latitude = 40.76473
        AND rounded_longitude = -73.96636)

    OR (station_name = '51 STREET'
        AND rounded_latitude = 40.75712
        AND rounded_longitude = -73.97191)

    OR (station_name = '57 STREET'
        AND rounded_latitude = 40.76552
        AND rounded_longitude = -73.98004)

    OR (station_name = 'SOUTH FERRY'
        AND rounded_latitude = 40.70151
        AND rounded_longitude = -74.01255)

    OR (station_name = 'LORIMER STREET'
        AND rounded_latitude = 40.71407
        AND rounded_longitude = -73.94937)

    OR (station_name = 'EAST TREMONT AVE.-WEST FARMS S'
        AND rounded_latitude = 40.84023
        AND rounded_longitude = -73.8801)

    OR (station_name = 'GRAND AVE.-NEWTON'
        AND rounded_latitude = 40.73675
        AND rounded_longitude = -73.87767)

    OR (station_name = 'WILLETS POINT-SHEA STADIUM'
        AND rounded_latitude = 40.75534
        AND rounded_longitude = -73.84325)

    OR (station_name = '42 ST.-GRAND CENTRAL'
        AND rounded_latitude = 40.75353
        AND rounded_longitude = -73.99454)

    OR (station_name = '82 ST.-JACKSON HEIGHTS'
        AND rounded_latitude = 40.74763
        AND rounded_longitude = -73.88394)

    OR (station_name = 'BEVERLY ROAD'
        AND rounded_latitude = 40.64513
        AND rounded_longitude = -73.94896)

    OR (station_name = 'DITMARS BLVD.-ASTORIA'
        AND rounded_latitude = 40.77613
        AND rounded_longitude = -73.9107)

    OR (station_name = '42 ST.-TIMES SQUARE'
        AND rounded_latitude = 40.75656
        AND rounded_longitude = -73.98611)

    OR (station_name = 'COURT SQUARE'
        AND rounded_latitude = 40.74648
        AND rounded_longitude = -73.94402)

    OR (station_name = 'METROPOLITAN AVENUE'
        AND rounded_latitude = 40.7138
        AND rounded_longitude = -73.95159)

    OR (station_name = 'PRESIDENT STREET'
        AND rounded_latitude = 40.66807
        AND rounded_longitude = -73.95067)

    OR (station_name = '174-175 STREETS'
        AND rounded_latitude = 40.84687
        AND rounded_longitude = -73.90875);


-- Review the next group of station matches.

UPDATE station_match_review
SET
    review_status = CASE
        WHEN station_name = 'BAYCHESTER AVENUE'
            AND rounded_latitude = 40.8816
            AND rounded_longitude = -73.82964
            THEN 'INVESTIGATE'
        ELSE 'ACCEPT'
    END,

    review_reason = CASE
        WHEN station_name = '205 ST.-NORWOOD'
            THEN 'Same station, reversed naming'

        WHEN station_name = 'LEXINGTON AVENUE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = '110 ST.-CENTRAL PARK NORTH'
            THEN 'Same station, alternate naming'

        WHEN station_name = 'LAWRENCE STREET'
            THEN 'Legacy/component name of same MTA complex'

        WHEN station_name = '23 STREET'
            THEN 'Same station, alternate naming'

        WHEN station_name = '241 ST.-WAKEFIELD'
            THEN 'Same station, reversed naming'

        WHEN station_name = '42 ST.-TIMES SQUARE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'COURT STREET'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'MT. EDEN AVENUE'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '110 ST.-CATHEDRAL PKWY.'
            THEN 'Same station, reordered naming'

        WHEN station_name = 'BAYCHESTER AVENUE'
            THEN 'NYPD station name conflicts with distant MTA candidate'

        WHEN station_name = 'GUN HILL ROAD'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'MYRTLE-WILLOUGHBY AVENUES'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '7TH AVENUE'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '23 STREET-ELY AVENUE'
            THEN 'Legacy/component name of same MTA complex'

        WHEN station_name = '8 AVENUE'
            THEN 'Named component of same MTA complex'

        WHEN station_name = 'LEXINGTON AVE.'
            THEN 'Coordinate identifies Lexington Av/59 St complex'

        WHEN station_name = 'ST. LAWRENCE AVENUE'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = '33 STREET'
            THEN 'Named component of same station'

        WHEN station_name = 'ATLANTIC AVENUE'
            THEN 'Named component of same MTA complex'
    END

WHERE
    (station_name = '205 ST.-NORWOOD'
        AND rounded_latitude = 40.87498
        AND rounded_longitude = -73.87946)

    OR (station_name = 'LEXINGTON AVENUE'
        AND rounded_latitude = 40.75837
        AND rounded_longitude = -73.97099)

    OR (station_name = '110 ST.-CENTRAL PARK NORTH'
        AND rounded_latitude = 40.79824
        AND rounded_longitude = -73.95246)

    OR (station_name = 'LAWRENCE STREET'
        AND rounded_latitude = 40.69219
        AND rounded_longitude = -73.98627)

    OR (station_name = '23 STREET'
        AND rounded_latitude = 40.74018
        AND rounded_longitude = -73.98636)

    OR (station_name = '241 ST.-WAKEFIELD'
        AND rounded_latitude = 40.90348
        AND rounded_longitude = -73.85034)

    OR (station_name = '42 ST.-TIMES SQUARE'
        AND rounded_latitude = 40.75475
        AND rounded_longitude = -73.98789)

    OR (station_name = 'COURT STREET'
        AND rounded_latitude = 40.69428
        AND rounded_longitude = -73.99242)

    OR (station_name = 'MT. EDEN AVENUE'
        AND rounded_latitude = 40.84434
        AND rounded_longitude = -73.91474)

    OR (station_name = '110 ST.-CATHEDRAL PKWY.'
        AND rounded_latitude = 40.80417
        AND rounded_longitude = -73.9667)

    OR (station_name = 'BAYCHESTER AVENUE'
        AND rounded_latitude = 40.8816
        AND rounded_longitude = -73.82964)

    OR (station_name = 'GUN HILL ROAD'
        AND rounded_latitude = 40.87055
        AND rounded_longitude = -73.84641)

    OR (station_name = 'MYRTLE-WILLOUGHBY AVENUES'
        AND rounded_latitude = 40.69538
        AND rounded_longitude = -73.94921)

    OR (station_name = '7TH AVENUE'
        AND rounded_latitude = 40.678
        AND rounded_longitude = -73.97305)

    OR (station_name = '23 STREET-ELY AVENUE'
        AND rounded_latitude = 40.74811
        AND rounded_longitude = -73.94735)

    OR (station_name = '8 AVENUE'
        AND rounded_latitude = 40.73975
        AND rounded_longitude = -74.00252)

    OR (station_name = 'LEXINGTON AVE.'
        AND rounded_latitude = 40.76223
        AND rounded_longitude = -73.96819)

    OR (station_name = 'ST. LAWRENCE AVENUE'
        AND rounded_latitude = 40.83162
        AND rounded_longitude = -73.86726)

    OR (station_name = '33 STREET'
        AND rounded_latitude = 40.74467
        AND rounded_longitude = -73.93168)

    OR (station_name = 'ATLANTIC AVENUE'
        AND rounded_latitude = 40.68508
        AND rounded_longitude = -73.97789);


-- Review the final high-priority station matches.

UPDATE station_match_review
SET
    review_status = CASE
        WHEN station_name = '14 STREET'
            AND rounded_latitude = 40.7372
            AND rounded_longitude = -73.98327
            THEN 'INVESTIGATE'
        ELSE 'ACCEPT'
    END,

    review_reason = CASE
        WHEN station_name = '14 STREET'
            THEN 'NYPD station name conflicts with nearest MTA candidate'

        WHEN station_name = '200 ST.-DYCKMAN ST.'
            AND rounded_latitude = 40.86159
            THEN 'Legacy/alternate name for Dyckman St 1 station'

        WHEN station_name = '200 ST.-DYCKMAN ST.'
            AND rounded_latitude = 40.86554
            THEN 'Legacy/alternate name for Dyckman St A station'

        WHEN station_name = '148 ST.-HARLEM'
            THEN 'Same station, reversed naming'

        WHEN station_name = 'GUN HILL ROAD'
            THEN 'Same station, abbreviated naming'

        WHEN station_name = 'VAN WYCK BLVD.-BRIARWOOD'
            THEN 'Legacy/alternate station name'
    END

WHERE
    (station_name = '14 STREET'
        AND rounded_latitude = 40.7372
        AND rounded_longitude = -73.98327)

    OR (station_name = '200 ST.-DYCKMAN ST.'
        AND rounded_latitude = 40.86159
        AND rounded_longitude = -73.92474)

    OR (station_name = '200 ST.-DYCKMAN ST.'
        AND rounded_latitude = 40.86554
        AND rounded_longitude = -73.92727)

    OR (station_name = '148 ST.-HARLEM'
        AND rounded_latitude = 40.82357
        AND rounded_longitude = -73.93767)

    OR (station_name = 'GUN HILL ROAD'
        AND rounded_latitude = 40.87763
        AND rounded_longitude = -73.86738)

    OR (station_name = 'VAN WYCK BLVD.-BRIARWOOD'
        AND rounded_latitude = 40.70968
        AND rounded_longitude = -73.82003);


-- Correct Columbus Circle where the recorded NYPD coordinate
-- produced the wrong nearest MTA station.

UPDATE station_match_review
SET
    candidate_station_complex = '59 St-Columbus Circle (1,A,C,B,D)',
    station_complex_id = 614,
    review_status = 'ACCEPT',
    review_reason = 'Corrected using NYPD station name; recorded coordinate produced incorrect nearest station'
WHERE station_name = '59 ST.-COLUMBUS CIRCLE'
    AND rounded_latitude = 40.76502
    AND rounded_longitude = -73.98484;


-- Correct Baychester Avenue.

UPDATE station_match_review
SET
    candidate_station_complex = 'Baychester Av (5)',
    station_complex_id = 443,
    review_status = 'ACCEPT',
    review_reason = 'Corrected using NYPD station name; recorded coordinate produced incorrect nearest station'
WHERE station_name = 'BAYCHESTER AVENUE'
    AND rounded_latitude = 40.8816
    AND rounded_longitude = -73.82964;


-- Correct Times Square cluster incorrectly assigned to Penn Station.

UPDATE station_match_review
SET
    candidate_station_complex = 'Times Sq-42 St/Port Authority Bus Terminal (1,2,3,7,A,C,E,N,Q,R,W,S)',
    station_complex_id = 611,
    review_status = 'ACCEPT',
    review_reason = 'Corrected using NYPD station name; recorded coordinate produced incorrect nearest station'
WHERE station_name = '42 ST.-TIMES SQUARE'
    AND rounded_latitude = 40.75353
    AND rounded_longitude = -73.99454;


-- Correct Grand Central cluster incorrectly assigned to Penn Station.

UPDATE station_match_review
SET
    candidate_station_complex = 'Grand Central-42 St (4,5,6,7,S)',
    station_complex_id = 610,
    review_status = 'ACCEPT',
    review_reason = 'Corrected using NYPD station name; recorded coordinate produced incorrect nearest station'
WHERE station_name = '42 ST.-GRAND CENTRAL'
    AND rounded_latitude = 40.75353
    AND rounded_longitude = -73.99454;


-- Check Transit District for the remaining Atlantic Avenue
-- and 14 Street cases.

SELECT
    STATION_NAME,
    TRANSIT_DISTRICT,
    COUNT(*) AS complaints
FROM nypd_complaints
WHERE
    (
        STATION_NAME = 'ATLANTIC AVENUE'
        AND ROUND(latitude, 5) = 40.69022
        AND ROUND(longitude, 5) = -73.96028
    )
    OR
    (
        STATION_NAME = '14 STREET'
        AND ROUND(latitude, 5) = 40.7372
        AND ROUND(longitude, 5) = -73.98327
    )
GROUP BY
    STATION_NAME,
    TRANSIT_DISTRICT;


-- Correct Atlantic Avenue using station name and Transit District 32.

UPDATE station_match_review
SET
    candidate_station_complex = 'Atlantic Av-Barclays Ctr (2,3,4,5,B,D,N,Q,R)',
    station_complex_id = 617,
    review_status = 'ACCEPT',
    review_reason = 'Corrected using station name and Transit District 32; recorded coordinate produced incorrect nearest station'
WHERE station_name = 'ATLANTIC AVENUE'
    AND rounded_latitude = 40.69022
    AND rounded_longitude = -73.96028;


-- Summarize the final high-priority review status.

SELECT
    review_status,
    COUNT(*) AS coordinate_clusters,
    SUM(complaint_count) AS complaints
FROM station_match_review
GROUP BY review_status;