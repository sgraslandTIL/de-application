import argparse
import csv
from datetime import date
from pathlib import Path

import duckdb

DB_PATH = "tides.duckdb"
OUTPUT_PATH = Path("output/alerts.csv")
DISPLAY_NAME = "Port Boca Grande"


def day_text(d):
    return f"{d:%A, %B} {d.day}"


def time_text(t):
    return f"{t:%I:%M %p}".lstrip("0")


def message(first_day, last_day, peak_at, peak_ft):
    if first_day == last_day:
        when = f"on {day_text(first_day)}"
    else:
        when = f"from {day_text(first_day)} to {day_text(last_day)}"
    inches = round(peak_ft * 12)
    return (
        f"King tide alert for {DISPLAY_NAME}: high water is predicted {when}. "
        f"The highest tide is expected {day_text(peak_at)} at {time_text(peak_at)}, "
        f"about {inches} inches above a normal high tide. "
        "Add slack to your dock lines and move anything stored on the dock. "
        "Wind can push the water higher than predicted."
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", type=date.fromisoformat, default=date.today())
    run_date = parser.parse_args().date

    con = duckdb.connect(DB_PATH, read_only=True)
    rows = con.execute("""
        select alert_id, send_date, first_day, last_day,
               peak_tide_at_local, peak_above_mhhw_ft
        from mart_alerts
        order by send_date
    """).fetchall()
    con.close()

    OUTPUT_PATH.parent.mkdir(exist_ok=True)
    with OUTPUT_PATH.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["alert_id", "send_date", "first_day", "last_day",
                         "peak_tide_at_local", "peak_above_mhhw_ft", "message"])
        for alert_id, send_date, first_day, last_day, peak_at, peak_ft in rows:
            writer.writerow([alert_id, send_date, first_day, last_day,
                             peak_at, peak_ft, message(first_day, last_day, peak_at, peak_ft)])
    print(f"Wrote {len(rows)} alerts to {OUTPUT_PATH}")

    due = [r for r in rows if r[1] == run_date]
    if not due:
        print(f"No alerts to send on {run_date}")
    for alert_id, send_date, first_day, last_day, peak_at, peak_ft in due:
        print(f"\nSend on {send_date}:\n{message(first_day, last_day, peak_at, peak_ft)}")


if __name__ == "__main__":
    main()