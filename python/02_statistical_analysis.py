import pandas as pd
import numpy as np
from scipy.stats import linregress


# ------------------------------------------------------------
# Ridership vs. complaint volume
# ------------------------------------------------------------

volume_data = pd.read_csv(
    "ridership_complaint_correlation.csv"
)

volume_pearson = volume_data["total_ridership"].corr(
    volume_data["total_complaints"],
    method="pearson"
)

volume_spearman = volume_data["total_ridership"].corr(
    volume_data["total_complaints"],
    method="spearman"
)

print("Ridership vs. complaint volume")
print("Pearson correlation:", volume_pearson)
print("Spearman correlation:", volume_spearman)


# ------------------------------------------------------------
# Ridership vs. rider-adjusted complaint rate
# ------------------------------------------------------------

rate_data = pd.read_csv(
    "ridership_complaint_rate_analysis.csv"
)

rate_pearson = rate_data["total_ridership"].corr(
    rate_data["complaints_per_100k_riders"],
    method="pearson"
)

rate_spearman = rate_data["total_ridership"].corr(
    rate_data["complaints_per_100k_riders"],
    method="spearman"
)

print("\nRidership vs. complaint rate")
print("Pearson correlation:", rate_pearson)
print("Spearman correlation:", rate_spearman)


# ------------------------------------------------------------
# Median household income vs. rider-adjusted complaint rate
# ------------------------------------------------------------

income_data = pd.read_csv(
    "income_complaint_rate_analysis.csv"
)

income_pearson = income_data["median_household_income"].corr(
    income_data["complaints_per_100k_riders"],
    method="pearson"
)

income_spearman = income_data["median_household_income"].corr(
    income_data["complaints_per_100k_riders"],
    method="spearman"
)

print("\nMedian household income vs. complaint rate")
print("Pearson correlation:", income_pearson)
print("Spearman correlation:", income_spearman)


# ------------------------------------------------------------
# Residual analysis
# ------------------------------------------------------------
# The residual analysis uses income_complaint_rate_analysis.csv,
# so both ridership and income models use the same station sample:
# stations with at least 500,000 annual riders and non-missing income.


# Log-transform ridership because station ridership is highly skewed.
income_data["log_ridership"] = np.log10(
    income_data["total_ridership"]
)


# Model complaint rate as a function of log ridership.
ridership_model = linregress(
    income_data["log_ridership"],
    income_data["complaints_per_100k_riders"]
)


# Calculate the complaint rate expected from the ridership model.
income_data["expected_rate_from_ridership"] = (
    ridership_model.intercept
    + ridership_model.slope * income_data["log_ridership"]
)


# Calculate ridership residuals.
# Positive residual = higher complaint rate than the model predicts.
# Negative residual = lower complaint rate than the model predicts.
income_data["ridership_residual"] = (
    income_data["complaints_per_100k_riders"]
    - income_data["expected_rate_from_ridership"]
)


# Model complaint rate as a function of median household income.
income_model = linregress(
    income_data["median_household_income"],
    income_data["complaints_per_100k_riders"]
)


# Calculate the complaint rate expected from the income model.
income_data["expected_rate_from_income"] = (
    income_model.intercept
    + income_model.slope * income_data["median_household_income"]
)


# Calculate income residuals.
income_data["income_residual"] = (
    income_data["complaints_per_100k_riders"]
    - income_data["expected_rate_from_income"]
)


# ------------------------------------------------------------
# Outlier results
# ------------------------------------------------------------

print("\nHigher complaint rate than expected from ridership:")
print(
    income_data.nlargest(
        10,
        "ridership_residual"
    )[
        [
            "station_complex",
            "total_ridership",
            "complaints_per_100k_riders",
            "ridership_residual"
        ]
    ].to_string(index=False)
)


print("\nHigher complaint rate than expected from neighborhood income:")
print(
    income_data.nlargest(
        10,
        "income_residual"
    )[
        [
            "station_complex",
            "median_household_income",
            "complaints_per_100k_riders",
            "income_residual"
        ]
    ].to_string(index=False)
)


print("\nLower complaint rate than expected from neighborhood income:")
print(
    income_data.nsmallest(
        10,
        "income_residual"
    )[
        [
            "station_complex",
            "median_household_income",
            "complaints_per_100k_riders",
            "income_residual"
        ]
    ].to_string(index=False)
)