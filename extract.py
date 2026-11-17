import json
from datetime import datetime, timezone
from pathlib import Path

import requests

import time

DATA_URL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
DATUMS_URL = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/{station_id}/datums.json"

BEGIN_DATE = "20260801"
END_DATE = "20270731"

STATIONS_URL = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json"

# Charlotte Harbor bounding box
MIN_LAT, MAX_LAT = 26.7000, 27.0090
MIN_LNG, MAX_LNG = -82.2800, -81.9597

RAW_DIR = Path("data/raw")


def pulled_at():
    """Current UTC time, safe to use in a Windows file name."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")


def save_raw(text, subfolder, name):
    """Save a response exactly as the API returned it."""
    folder = RAW_DIR / subfolder
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{name}_{pulled_at()}.json"
    path.write_text(text, encoding="utf-8")
    return path


def fetch_station_list():
    response = requests.get(STATIONS_URL, params={"type": "tidepredictions"}, timeout=60)
    response.raise_for_status()
    return response.text


def stations_in_box(raw_text):
    stations = json.loads(raw_text)["stations"]
    return [
        s for s in stations
        if s["lat"] is not None and s["lng"] is not None
        and MIN_LAT <= s["lat"] <= MAX_LAT
        and MIN_LNG <= s["lng"] <= MAX_LNG
    ]
def latest_raw(subfolder):
    """Most recent raw file in a folder, or None if there isn't one."""
    files = sorted((RAW_DIR / subfolder).glob("*.json"))
    return files[-1] if files else None


def fetch_predictions(station_id):
    params = {
        "product": "predictions",
        "station": station_id,
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
        raise RuntimeError(f"{station_id}: {response.json()['error']['message']}")
    return response.text


def fetch_datums(station_id):
    response = requests.get(DATUMS_URL.format(station_id=station_id), timeout=60)
    if response.status_code == 404:
        return None
    response.raise_for_status()
    return response.text

if __name__ == "__main__":
    existing = latest_raw("stations")
    if existing:
        raw = existing.read_text(encoding="utf-8")
        print(f"Using {existing}")
    else:
        raw = fetch_station_list()
        print(f"Saved {save_raw(raw, 'stations', 'tidepredictions')}")

    for s in stations_in_box(raw):
        station_id = s["id"]
        print(f"Saved {save_raw(fetch_predictions(station_id), 'predictions', station_id)}")
        time.sleep(1)

        datums = fetch_datums(station_id)
        if datums is None:
            print(f"No datums for {station_id}, skipped")
        else:
            print(f"Saved {save_raw(datums, 'datums', station_id)}")
        time.sleep(1)