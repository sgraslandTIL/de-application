from pathlib import Path

import duckdb
import sys

TEST_FILES = sorted(Path("sql/tests").glob("*.sql"))

DB_PATH = "tides.duckdb"

SQL_FILES = [
    "sql/staging/stg_predictions.sql",
    "sql/staging/stg_datums.sql",
    "sql/staging/stg_stations.sql",
    "sql/mart/mart_high_tides.sql",
    "sql/mart/mart_alerts.sql"
]

def run_tests(con):
    failures = 0
    for path in TEST_FILES:
        rows = con.execute(path.read_text(encoding="utf-8")).fetchall()
        if rows:
            failures += 1
            print(f"FAIL {path.name}: {len(rows)} rows")
            for row in rows[:5]:
                print(f"  {row}")
        else:
            print(f"PASS {path.name}")
    return failures

def main():
    con = duckdb.connect(DB_PATH)
    for path in SQL_FILES:
        print(f"Running {path}")
        con.execute(Path(path).read_text(encoding="utf-8"))
    failures = run_tests(con)
    con.close()
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()