from pathlib import Path

import duckdb

DB_PATH = "tides.duckdb"

SQL_FILES = [
    "sql/staging/stg_predictions.sql",
    "sql/staging/stg_datums.sql",
    "sql/staging/stg_stations.sql",
]

def main():
    con = duckdb.connect(DB_PATH)
    for path in SQL_FILES:
        print(f"Running {path}")
        con.execute(Path(path).read_text(encoding="utf-8"))
    con.close()


if __name__ == "__main__":
    main()