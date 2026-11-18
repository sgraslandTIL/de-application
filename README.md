# Port Boca Grande king tide alerts

## What I built and who for

I built an alert system for boat owners who keep their boats at Port Boca Grande, at the mouth of Charlotte Harbor, Florida. Many of them live somewhere else, sometimes out of state, so they may not know a king tide (an unusually high tide) is coming until it has already caused damage.

The alert gives them three days' notice of a predicted high tide. That's enough time to travel down or arrange help to add slack to dock lines and move items off the dock.

Public flood alerts don't cover this well. NOAA's flood thresholds are set for when water reaches land, like streets and buildings. Docks and boats feel high water much sooner, so a tide that's routine by NOAA's standards can still catch a boat owner off guard.

This is a proof of concept for one station. I started with eight stations across Charlotte Harbor, but the three stations NOAA predicts from a station outside the harbor never crossed my threshold. Rather than ship an alert that silently never fires for some marinas, I scoped it down to one station I could stand behind.

### What a boat owner receives

Here's the alert for the late-November king tide, sent on Saturday, November 21, 2026:

> King tide alert for Port Boca Grande: unusually high tides are predicted from Tuesday, November 24 to Friday, November 27. The highest tide is expected Wednesday, November 25 at 11:39 PM, about 9 inches above a normal high tide. Add slack to your dock lines and move anything stored on the dock. Wind can push the water higher than predicted.

Over the year from August 2026 to July 2027, the pipeline produces six alerts:

| Alert sent | High tides expected | Peak |
|---|---|---|
| Aug 7, 2026 | Aug 10 to 11 | 8 inches, Aug 11 at 11:39 AM |
| Sep 28, 2026 | Oct 1 to 2 | 7 inches, Oct 1 at 2:32 AM |
| Oct 24, 2026 | Oct 27 to 30 | 9 inches, Oct 29 at 1:29 AM |
| Nov 21, 2026 | Nov 24 to 27 | 9 inches, Nov 25 at 11:39 PM |
| Jun 30, 2027 | Jul 3 to 4 | 8 inches, Jul 4 at 12:28 PM |
| Jul 28, 2027 | Jul 31 | 7 inches, Jul 31 at 10:46 AM |

Every alert is in `output/alerts.csv`, and you can reproduce them with the steps in "How to run it."

## The data

I used two NOAA CO-OPS APIs, which need no key:

- The [data API](https://api.tidesandcurrents.noaa.gov/api/prod/) for high and low tide predictions at Port Boca Grande (station 8725577), from August 1, 2026 to July 31, 2027, in feet above Mean Lower Low Water, with times in GMT.
- The [metadata API](https://api.tidesandcurrents.noaa.gov/mdapi/prod/) for the station's details and its tidal datums, the reference water levels that let me compare a tide to a typical high tide.

A few things about the data shaped the pipeline:

- **The responses aren't paginated.** Instead, each request covers a date range, and NOAA allows up to 10 years of high and low predictions in one request, so a year fits in one call.
- **Errors don't always look like errors.** A bad request can come back as a normal response with an `error` message inside, so the extraction script checks for it.
- **Port Boca Grande has mixed tides.** It usually has two high tides a day, but one is much smaller, so the station never has two highs above the threshold on the same day.
- **NOAA publishes no flood threshold for this station,** so I set my own (see below).

This data is in the US public domain, so it can be published.

## How it works

The pipeline runs in three steps, and only the first one talks to NOAA.

1. **`extract.py`** pulls the station details, predictions, and datums, and saves each response exactly as it came back, under `data/raw/`. Each file name includes the station ID and the UTC time it was pulled, so a new pull never overwrites an old one. If a file already exists, the script skips that request, so reruns don't repeat API calls. It also pauses between requests, as NOAA asks.
2. **`transform.py`** runs SQL files in order against a DuckDB database, then runs the data tests. Every run rebuilds every table from the raw files. The data is small, so a full rebuild takes seconds and always gives the same result from the same files.
3. **`alerts.py`** turns the alert table into messages a boat owner would read, and writes them to `output/alerts.csv`.

### The tables

| Layer | Table | What it does |
|---|---|---|
| Staging | `stg_predictions` | One row per tide, with the time as a timestamp, the height as a number, and `high` or `low`. If the same tide appears in more than one pull, it keeps the most recent. |
| Staging | `stg_datums` | One row per station, with the gap between Mean Higher High Water and Mean Lower Low Water. At Port Boca Grande, that's 1.56 feet. |
| Staging | `stg_stations` | The station's ID, name, tide type, and coordinates. |
| Mart | `mart_high_tides` | Every high tide, its height above a normal high tide, its time in Florida, and whether it crosses the threshold. |
| Mart | `mart_alerts` | One row per king tide event, with its first and last day, its peak, and the date the alert goes out. |

### The alert threshold

An alert fires when a predicted high tide reaches 0.6 feet or more above Mean Higher High Water, the average height of the day's highest tide. This is a boating advisory, not a flood warning. Docks and boats feel high water much sooner than land does: lines tighten and fixed docks lose clearance long before a road floods. I grew up on the water, and more than once I pulled into the marina to find the tide higher than I expected and had to rush to fix the lines. That's the moment this alert is meant to prevent.

I chose 0.6 feet by testing several margins against a year of predictions (see `analysis/threshold_calibration.sql`). An event is a run of days with a high tide over the line, and each event gets one alert:

| Margin | Events (alerts) | Days over the line |
|---|---|---|
| 0.50 ft | ? | ? |
| 0.55 ft | ? | ? |
| 0.60 ft | 6 | 14 |
| 0.65 ft | ? | ? |
| 0.70 ft | ? | ? |

At 0.6 feet, owners get six alerts a year, covering 14 days of high tides. That's rare enough to take seriously. It also leaves room for wind, which can push real water higher than predicted. A tide exactly at 0.6 feet counts, because it carries the same risk as one just above it.

The threshold stays fixed on purpose. Think of it as a line painted on a dock post. If the sea rises over the years, water reaches the line more often, and owners get more alerts. That's right, because their boats really are at risk more often. If I repainted the line every year to keep the same number of alerts, I'd have to paint it higher as the water rose, and the alert would hide the change.

### Other decisions

- **Times are stored in GMT and converted to Florida time only for the alert.** Local time repeats an hour in November and skips one in March, which could duplicate or lose a tide.
- **One alert per king tide, not per day.** Consecutive days above the threshold become one event, and a single day just below the line doesn't split it. The water is still high on that day, and an owner planning a trip needs to know the whole span.
- **The alert goes out three days before the first day of the event,** not the peak, because owners need to act before the water rises.
- **Heights are rounded to three decimals,** NOAA's published precision. I first rounded to two, and a check against my calibration query showed four tides on the wrong side of the threshold. Rounding to three fixed it without losing real information.
- **Messages give the height in inches above a normal high tide,** because "0.726 feet above Mean Higher High Water" means nothing to a boat owner.

### Testing

`transform.py` runs six tests after every build and stops with an error if any fail. They check that no tide appears twice, no key column is empty, the station has datums, the datums are in feet, the station table isn't empty, and no alert ID repeats.

To check what happens on a second run, I copied the predictions file under a later timestamp and rebuilt. The tide count stayed the same, the table kept the newer copy, and every test passed.

### What this shape makes easy and hard

It's easy to change the threshold or the gap rule, since each is one number at the top of its SQL file. It's harder to bring in weather, since the tables only know predicted tides, or to alert by marina, since nothing maps marinas to stations yet.

## How to run it

You need Git and Python 3.12 or later. I built it with Python 3.14 on Windows.

The raw NOAA responses are committed in `data/raw/`, and the API needs no key, so everything below runs from a clean clone.

```
git clone https://github.com/sgraslandTIL/de-application.git
cd de-application
python -m venv .venv
```

Turn on the virtual environment. On Windows (PowerShell):

```
.venv\Scripts\Activate.ps1
```

On macOS or Linux:

```
source .venv/bin/activate
```

Then install the requirements, build the tables, and write the alerts:

```
pip install -r requirements.txt
python transform.py
python alerts.py --date 2026-11-21
```

- `transform.py` builds `tides.duckdb` from the raw files, then runs the data tests.
- `alerts.py` writes every alert to `output/alerts.csv`, then prints any alert due on the date you give it. `2026-11-21` shows the November king tide alert. Leave out `--date` to check today.

`extract.py` pulls data from NOAA. You don't need to run it, because the raw data is already committed, and it skips anything already saved. To pull fresh data, delete Port Boca Grande's files from `data/raw/` first, then run `python extract.py`.

## What I would do next

- **Send the alerts for real.** Connect an email or text service and a sign-up form, with the credentials kept out of the repository. I'd also build a Tableau Pulse metric on the alerts, so owners can follow it.
- **Add the rest of Charlotte Harbor.** Find out why the stations NOAA predicts from outside the harbor never cross the threshold, and calibrate each station on its own tides.
- **Check predictions against real water.** Compare predicted tides with observed levels from a nearby active NOAA gauge, and lower the threshold if real tides often run higher than predicted.
- **Pull on a rolling window.** Right now the script skips a file if it exists. A daily run would need to check the latest saved tide and request only the days after it.
- **Test more years.** Tides follow an 18.6-year lunar cycle, so one year may run high or low. NOAA allows 10 years of predictions in one request.
- **Review the threshold when NOAA updates its datums,** since that's where sea level rise reaches this pipeline.
- **Add wind forecasts,** so an alert can warn when weather is likely to push water above the prediction.

## Where AI helped

I used Claude as a coach through the whole build, and ChatGPT for two research questions about tides and thresholds. Claude wrote most of the code from decisions I made: the subject, the audience, the station, the 0.6-foot threshold, counting a tide exactly at the line, merging events across a one-day gap, and scoping down to one station. I first wanted incremental loading for the tables too, and changed my mind once I understood it wouldn't reduce API calls. AI also made mistakes I caught: it underestimated the number of tides, and its first rounding choice put four tides on the wrong side of the threshold. I rejected ChatGPT's advice to compare unrounded values, since rounding to NOAA's precision loses nothing.