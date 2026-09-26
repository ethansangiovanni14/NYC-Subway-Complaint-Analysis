import pandas as pd
import geopandas as gpd
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
RAW_DATA_DIR = BASE_DIR / "raw_data"


# Load MTA station locations.
stations = pd.read_csv(DATA_DIR / "mta_station_locations.csv")

print("MTA stations:", len(stations))


# Convert MTA latitude and longitude into geographic points.
stations_gdf = gpd.GeoDataFrame(
    stations,
    geometry=gpd.points_from_xy(
        stations["longitude"],
        stations["latitude"]
    ),
    crs="EPSG:4326"
)


# Load the 2024 New York Census tract boundaries.
tracts = gpd.read_file(RAW_DATA_DIR / "tl_2024_36_tract.shp")

print("Census tracts:", len(tracts))
print("Original Census tract CRS:", tracts.crs)


# Convert Census tracts to the same coordinate system as the MTA stations.
tracts = tracts.to_crs("EPSG:4326")

print("Converted Census tract CRS:", tracts.crs)


# Match each MTA station point to the Census tract that contains it.
station_tracts = gpd.sjoin(
    stations_gdf,
    tracts[["GEOID", "geometry"]],
    how="left",
    predicate="within"
)


# Check whether any stations failed to match to a Census tract.
missing_tracts = station_tracts["GEOID"].isna().sum()

print("Stations missing a Census tract:", missing_tracts)


# Load Census median household income data.
income = pd.read_csv(RAW_DATA_DIR / "Census data.csv")


# Convert Census identifiers and income values to strings for cleaning.
income["GEO_ID"] = income["GEO_ID"].astype("string")
income["B19013_001E"] = income["B19013_001E"].astype("string")


# Remove the Census prefix so GEO_ID matches the tract GEOID.
income["GEOID"] = income["GEO_ID"].str.replace(
    "1400000US",
    "",
    regex=False
)


# Flag Census income values reported as 250,000+.
income["income_topcoded"] = income["B19013_001E"].str.contains(
    r"\+$",
    na=False
)


# Remove commas and the + symbol so income can be converted to numeric.
income["median_household_income"] = (
    income["B19013_001E"]
    .str.replace(",", "", regex=False)
    .str.replace("+", "", regex=False)
)


# Convert income values to numeric.
# Census values shown as "-" become missing values (NaN).
income["median_household_income"] = pd.to_numeric(
    income["median_household_income"],
    errors="coerce"
)


# Merge Census income onto each MTA station using Census tract GEOID.
station_income = station_tracts.merge(
    income[
        [
            "GEOID",
            "median_household_income",
            "income_topcoded"
        ]
    ],
    on="GEOID",
    how="left"
)


# Count stations where Census did not provide a usable income estimate.
missing_income_count = station_income[
    "median_household_income"
].isna().sum()

print("Stations missing median household income:", missing_income_count)


# Show the stations that are missing income.
missing_income = station_income[
    station_income["median_household_income"].isna()
][
    [
        "station_complex_id",
        "station_complex",
        "GEOID"
    ]
]

print("\nStations with missing income:")
print(missing_income)


# Show the original Census values for the missing-income tracts.
missing_geoids = station_income.loc[
    station_income["median_household_income"].isna(),
    "GEOID"
].unique()

print("\nOriginal Census values for missing-income tracts:")
print(
    income[
        income["GEOID"].isin(missing_geoids)
    ][
        [
            "GEOID",
            "NAME",
            "B19013_001E"
        ]
    ]
)


# Create the final station-income dataset.
station_income_clean = station_income[
    [
        "station_complex_id",
        "station_complex",
        "GEOID",
        "median_household_income",
        "income_topcoded"
    ]
]


# Validate the final row count.
print("\nFinal station-income rows:", len(station_income_clean))


# Export the clean station-income dataset.
station_income_clean.to_csv(
    DATA_DIR / "station_income.csv",
    index=False
)

print("station_income.csv created successfully.")