import time
from datetime import datetime, timezone
from pathlib import Path

import requests

STATION_ID = "8725577"  # Port Boca Grande, Charlotte Harbor

BEGIN_DATE = "20260801"
END_DATE = "20270731"

STATION_URL = f"https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/{STATION_ID}"
DATA_URL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

RAW_DIR = Path("data/raw")


def pulled_at():
    """Current UTC time, safe to use in a Windows file name."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")


def save_raw(text, subfolder):
    """Save a response exactly as the API returned it."""
    folder = RAW_DIR / subfolder
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{STATION_ID}_{pulled_at()}.json"
    path.write_text(text, encoding="utf-8")
    return path


def already_saved(subfolder):
    return any((RAW_DIR / subfolder).glob(f"{STATION_ID}_*.json"))


def fetch_station():
    response = requests.get(f"{STATION_URL}.json", timeout=60)
    response.raise_for_status()
    return response.text


def fetch_predictions():
    params = {
        "product": "predictions",
        "station": STATION_ID,
        "begin_date": BEGIN_DATE,
        "end_date": END_DATE,
        "datum": "MLLW",
        "interval": "hilo",
        "units": "english",
        "time_zone": "gmt",
        "format": "json",
        "application": "de_application",
    }
    response = requests.get(DATA_URL, params=params, timeout=60)
    response.raise_for_status()
    if "error" in response.json():
        raise RuntimeError(response.json()["error"]["message"])
    return response.text


def fetch_datums():
    response = requests.get(f"{STATION_URL}/datums.json", timeout=60)
    response.raise_for_status()
    return response.text


STEPS = [
    ("stations", fetch_station),
    ("predictions", fetch_predictions),
    ("datums", fetch_datums),
]


if __name__ == "__main__":
    for subfolder, fetch in STEPS:
        if already_saved(subfolder):
            print(f"{subfolder} for {STATION_ID} already saved, skipped")
            continue
        print(f"Saved {save_raw(fetch(), subfolder)}")
        time.sleep(1)