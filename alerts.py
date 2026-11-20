# alerts.py
# Step 3 of the pipeline. Turns the alert table into messages a boat owner
# would read, writes every alert to output/alerts.csv, and prints any alert
# due on the run date.
# This script never talks to NOAA and only reads the database, so it runs
# from a clean clone once transform.py has built tides.duckdb.

import argparse            # for reading --date from the command line
import csv                 # for writing the output file
from datetime import date  # for the run date
from pathlib import Path   # for the output folder and file

import duckdb              # the database

# The database transform.py builds.
DB_PATH = "tides.duckdb"

# Where the alerts are written. The file is committed, so a reviewer can
# read the messages without running anything.
OUTPUT_PATH = Path("output/alerts.csv")

# NOAA's station name is "PORT BOCA GRANDE, CHARLOTTE HBR.", which reads
# badly in a text message, so the messages use this shorter name.
DISPLAY_NAME = "Port Boca Grande"


def day_text(d):
    # Formats a date like "Tuesday, November 24".
    # d.day gives the day with no leading zero. Python's code for that differs
    # between Windows and Mac, so reading d.day works on both.
    return f"{d:%A, %B} {d.day}"


def time_text(t):
    # Formats a time like "2:32 AM". %I gives "02", so lstrip removes the
    # leading zero.
    return f"{t:%I:%M %p}".lstrip("0")


def message(first_day, last_day, peak_at, peak_ft):
    # Builds the alert a boat owner reads.
    # A one-day event says "on" that day, and a longer one says "from" and "to".
    if first_day == last_day:
        when = f"on {day_text(first_day)}"
    else:
        when = f"from {day_text(first_day)} to {day_text(last_day)}"
    # Feet above MHHW means little to a boat owner, so convert to whole inches.
    # 0.726 feet x 12 = 8.7, which rounds to 9 inches.
    inches = round(peak_ft * 12)
    return (
        f"King tide alert for {DISPLAY_NAME}: high water is predicted {when}. "
        f"The highest tide is expected {day_text(peak_at)} at {time_text(peak_at)}, "
        f"about {inches} inches above a normal high tide. "
        "Add slack to your dock lines and move anything stored on the dock. "
        "Wind can push the water higher than predicted."
    )


def main():
    # Read the run date. --date 2026-11-21 checks that date, and leaving it
    # out uses today's date on the computer running the script.
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", type=date.fromisoformat, default=date.today())
    run_date = parser.parse_args().date

    # Open the database read-only, because this script never changes it.
    con = duckdb.connect(DB_PATH, read_only=True)
    rows = con.execute("""
        select alert_id, send_date, first_day, last_day,
               peak_tide_at_local, peak_above_mhhw_ft
        from mart_alerts
        order by send_date
    """).fetchall()
    con.close()

    # Write every alert to the CSV, creating the output folder if needed.
    # "w" replaces the file each run, so running twice never adds rows.
    OUTPUT_PATH.parent.mkdir(exist_ok=True)
    with OUTPUT_PATH.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["alert_id", "send_date", "first_day", "last_day",
                         "peak_tide_at_local", "peak_above_mhhw_ft", "message"])
        for alert_id, send_date, first_day, last_day, peak_at, peak_ft in rows:
            writer.writerow([alert_id, send_date, first_day, last_day,
                             peak_at, peak_ft, message(first_day, last_day, peak_at, peak_ft)])
    print(f"Wrote {len(rows)} alerts to {OUTPUT_PATH}")

    # Print the alerts due on the run date. r[1] is send_date, the second
    # column in the query above.
    due = [r for r in rows if r[1] == run_date]
    if not due:
        print(f"No alerts to send on {run_date}")
    for alert_id, send_date, first_day, last_day, peak_at, peak_ft in due:
        print(f"\nSend on {send_date}:\n{message(first_day, last_day, peak_at, peak_ft)}")


# Only runs when you call `python alerts.py` directly,
# not if another script imports this file.
if __name__ == "__main__":
    main()