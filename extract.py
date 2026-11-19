# extract.py
# Step 1 of the pipeline, and the only step that talks to NOAA.
# Pulls three things for one station and saves each response exactly as
# NOAA returned it, under data/raw/. Nothing is cleaned or changed here.
# Cleaning happens later, in the SQL that transform.py runs.

import time                                  # for the pause between API calls
from datetime import datetime, timezone      # for timestamping file names
from pathlib import Path                     # for building folder and file paths

import requests                              # for making the API calls

# ---------------------------------------------------------------------------
# Settings
# Kept at the top so they're easy to find and change in one place.
# ---------------------------------------------------------------------------

STATION_ID = "8725577"  # Port Boca Grande, Charlotte Harbor

# One year of predictions, written as YYYYMMDD because that's the format
# NOAA's API expects. NOAA allows up to 10 years of high/low predictions
# in one request, so a year fits in a single call and there's no pagination.
BEGIN_DATE = "20260801"
END_DATE = "20270731"

# Two different NOAA APIs:
# - the metadata API (mdapi) describes the station and its datums
# - the data API (datagetter) returns the tide predictions themselves
STATION_URL = f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/{STATION_ID}"
DATA_URL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

# Where raw responses are saved. Each type of response gets its own
# subfolder: data/raw/stations, data/raw/predictions, data/raw/datums.
RAW_DIR = Path("data/raw")


# ---------------------------------------------------------------------------
# Helper functions for saving files
# ---------------------------------------------------------------------------

def pulled_at():
    """Current UTC time, safe to use in a Windows file name."""
    # UTC, so the timestamp means the same thing wherever the script runs.
    # No colons in the format, because Windows doesn't allow them in file names.
    # Example output: 2026-11-17T153012Z
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")


def save_raw(text, subfolder):
    """Save a response exactly as the API returned it."""
    folder = RAW_DIR / subfolder
    # Create the folder if it doesn't exist yet. exist_ok=True means
    # no error if it's already there.
    folder.mkdir(parents=True, exist_ok=True)
    # File name = station ID + time of the pull,
    # for example 8725577_2026-11-17T153012Z.json.
    # Because the time is in the name, a new pull never overwrites an old one.
    path = folder / f"{STATION_ID}_{pulled_at()}.json"
    # Write the response text untouched, so the raw file matches what NOAA sent.
    path.write_text(text, encoding="utf-8")
    return path


def already_saved(subfolder):
    # True if this subfolder already holds any file for this station.
    # glob() looks for file names matching the pattern; * matches any timestamp.
    # This is what makes reruns safe: if the data is already saved,
    # the script skips the API call instead of pulling it again.
    return any((RAW_DIR / subfolder).glob(f"{STATION_ID}_*.json"))


# ---------------------------------------------------------------------------
# Fetch functions: one per thing pulled from NOAA
# Each returns the raw response text. None of them save anything.
# ---------------------------------------------------------------------------

def fetch_station():
    # Station details: name, tide type, coordinates.
    # timeout=60 stops the script waiting forever if NOAA doesn't respond.
    response = requests.get(f"{STATION_URL}.json", timeout=60)
    # Stop with an error if NOAA returned an HTTP error, such as 404 or 500.
    response.raise_for_status()
    return response.text


def fetch_predictions():
    # Query parameters. requests adds these to the URL as ?product=...&station=...
    params = {
        "product": "predictions",     # predicted tides, not observed water levels
        "station": STATION_ID,
        "begin_date": BEGIN_DATE,
        "end_date": END_DATE,
        "datum": "MLLW",              # heights measured from Mean Lower Low Water
        "interval": "hilo",           # only the high and low points, not every 6 minutes
        "units": "english",           # feet
        "time_zone": "gmt",           # GMT avoids daylight saving gaps and repeats
        "format": "json",
        "application": "de_application",  # tells NOAA who's calling, as their docs ask
    }
    response = requests.get(DATA_URL, params=params, timeout=60)
    response.raise_for_status()
    # NOAA sometimes reports a bad request as a normal, successful response
    # with an "error" message inside. raise_for_status() wouldn't catch that,
    # so check for it here and stop instead of saving an error as data.
    if "error" in response.json():
        raise RuntimeError(response.json()["error"]["message"])
    return response.text


def fetch_datums():
    # The station's tidal datums, including MHHW and MLLW.
    # transform.py later uses these to find the 1.56-foot gap.
    response = requests.get(f"{STATION_URL}/datums.json", timeout=60)
    response.raise_for_status()
    return response.text


# ---------------------------------------------------------------------------
# The list of steps to run: (subfolder name, function that fetches it)
# Adding a new pull means adding one line here and one fetch function above.
# ---------------------------------------------------------------------------

STEPS = [
    ("stations", fetch_station),
    ("predictions", fetch_predictions),
    ("datums", fetch_datums),
]


# ---------------------------------------------------------------------------
# Run the steps
# This block only runs when you call `python extract.py` directly,
# not if another script imports this file.
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    for subfolder, fetch in STEPS:
        # Rerun check: if this data is already saved, skip it.
        # On a second run, all three are skipped, so there are no API calls
        # and no new files.
        if already_saved(subfolder):
            print(f"{subfolder} for {STATION_ID} already saved, skipped")
            continue
        # Otherwise fetch the data, save it, and print where it went.
        print(f"Saved {save_raw(fetch(), subfolder)}")
        # Pause one second between calls so the script doesn't hit NOAA
        # with rapid-fire requests.
        time.sleep(1)