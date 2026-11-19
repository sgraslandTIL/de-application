# transform.py
# Step 2 of the pipeline. Builds the DuckDB database from the raw files
# that extract.py saved, then runs the data tests.
# This script never talks to NOAA, so it runs from a clean clone with no key.
# The cleaning logic itself lives in the SQL files. This script only runs
# them in the right order and reports on the tests.

from pathlib import Path   # for reading the SQL files

import duckdb              # the database
import sys                 # for exiting with an error code if a test fails

# Every .sql file in sql/tests, in alphabetical order.
# Each test is a query that returns rows only when something is wrong,
# so zero rows means the test passed.
TEST_FILES = sorted(Path("sql/tests").glob("*.sql"))

# The database file. DuckDB creates it the first time this runs.
# It's listed in .gitignore, because anyone can rebuild it from data/raw.
DB_PATH = "tides.duckdb"

# The build steps, in the order they must run.
# Staging comes first, because the marts read from the staging tables.
# mart_high_tides comes before mart_alerts for the same reason.
# Every file starts with "create or replace table", so each run replaces
# the old table with a fresh one instead of adding rows to it.
SQL_FILES = [
    "sql/staging/stg_predictions.sql",   # one row per tide, typed, duplicates removed
    "sql/staging/stg_datums.sql",        # the station's datums and the MHHW-MLLW gap
    "sql/staging/stg_stations.sql",      # station name, tide type, coordinates
    "sql/mart/mart_high_tides.sql",      # every high tide, its height above normal, threshold flag
    "sql/mart/mart_alerts.sql"           # one row per king tide event, with its send date
]

def run_tests(con):
    # Runs every test query and counts how many failed.
    failures = 0
    for path in TEST_FILES:
        # Run the test query and collect any rows it returns.
        rows = con.execute(path.read_text(encoding="utf-8")).fetchall()
        if rows:
            # Rows came back, so the test found a problem.
            failures += 1
            print(f"FAIL {path.name}: {len(rows)} rows")
            # Print up to five of the problem rows, to help find the cause.
            for row in rows[:5]:
                print(f"  {row}")
        else:
            # No rows, so nothing was wrong.
            print(f"PASS {path.name}")
    return failures

def main():
    # Open the database, creating the file if it doesn't exist yet.
    con = duckdb.connect(DB_PATH)
    # Run each SQL file in order. Each one rebuilds one table from scratch.
    for path in SQL_FILES:
        print(f"Running {path}")
        con.execute(Path(path).read_text(encoding="utf-8"))
    # Check the finished tables.
    failures = run_tests(con)
    con.close()
    # If any test failed, exit with code 1, the standard signal that a
    # program failed. The tables are already built at this point, so the
    # exit code is what tells you not to trust them.
    if failures:
        sys.exit(1)


# Only runs when you call `python transform.py` directly,
# not if another script imports this file.
if __name__ == "__main__":
    main()