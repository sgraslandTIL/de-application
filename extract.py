import json
from datetime import datetime, timezone
from pathlib import Path

import requests

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


if __name__ == "__main__":
    raw = fetch_station_list()
    path = save_raw(raw, "stations", "tidepredictions")
    print(f"Saved {path}")
    for s in stations_in_box(raw):
        print(s["id"], s["type"], s["lat"], s["lng"], s["name"])