# Contributing

How this project is put together, and the rules a change has to keep.

## What this is

A dbt analytics-engineering project over synthetic EHR data from Synthea. It
demonstrates, with runnable evidence, the core of an analytics engineer's job
in healthcare: staging raw feeds, dimensional models, data-quality tests,
documentation, and CI. It runs on DuckDB. Every number stated in the README or
the docs has to be reproducible from a `dbt build` of this repo.

## Run it

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python scripts/fetch_synthea.py
.venv/bin/dbt build
```

- Python 3.12 (`.python-version`). Versions are pinned in `requirements.txt`;
  bump them deliberately and run `dbt build` in the same commit.
- `scripts/fetch_synthea.py` lands 18 Synthea CSVs in `data/raw/synthea/`
  (gitignored, about 565 MB). Re-running is a no-op while every file is
  present at its recorded size; `--force` fetches again.
- Run dbt from the repo root. `profiles.yml` is repo-local, and dbt finds it
  only when launched from the directory that holds it. From anywhere else set
  `DBT_PROFILES_DIR` to the repo root.
- Run `dbt build --no-partial-parse` before committing yml changes, so
  deprecation warnings surface.
- One warning is expected and correct: the post-death encounter test,
  `docs/DECISIONS.md` section 15. A second warning is a regression.

## Layout

- `models/staging/<source>/`: `_<source>__sources.yml`,
  `_<source>__models.yml`, and one `stg_<source>__<entity>.sql` per entity.
- `models/marts/`: `_marts__models.yml`, one `dim_<entity>.sql` per dimension
  and one `fct_<event>.sql` per fact. Marts are where derived columns and
  business rules live, and where the Safe Harbor de-identification is applied.
- `macros/`: shared SQL expressions, one macro per file. A rule two models
  need lives here rather than in both.
- `tests/`: singular tests, one assertion per file, named `assert_<what>.sql`.
- `scripts/`: data fetching. Standard library only, so CI needs nothing extra.
- `docs/DECISIONS.md`: why things are the way they are. Read it before
  changing materialization, sources, the dataset, or the identifier policy.

## Conventions

- Sources are CSV files read in place by dbt-duckdb, every column as text.
  Staging does all renaming and casting and nothing else: no filtering, no
  derived columns. Every cast in a staging model is deliberate.
- Staging is materialized as tables on DuckDB. See `docs/DECISIONS.md`.
- Marts key on the natural identifiers the feed supplies. Most are Synthea
  UUIDs; `dim_date` keys on `date_id`, the day as a `YYYYMMDD` integer, and
  `dim_encounter_type` on the SNOMED CT code. No hashed surrogate keys.
- No model reads the clock. `current_date` and `now()` are banned, because
  every number the README states has to be reproducible from a `dbt build`.
- `dim_patient` is de-identified to HIPAA Safe Harbor and two tests enforce
  it, one on the column list and one on the data. Read `docs/DECISIONS.md`
  sections 12 and 19 before adding a column to it. Section 19 is there because
  the first version of that rule did not hold.
- A column is named for what it measures, not for what it was meant to
  measure. `docs/DECISIONS.md` section 20 is a list of four times that went
  wrong here.
- Generic tests use `data_tests:` with parameters nested under `arguments:`.
- A plain YAML scalar cannot contain a colon followed by a space, so a
  `description:` that needs one has to be a `>` block. dbt reports the failure
  as a parsing error on the yml line, not as a YAML error, which sends you
  looking in the wrong place.
- Column names are snake_case. Keys end in `_id`, dates in `_date`, timestamps
  in `_at`. Money is `decimal(18, 2)`; coordinates are `double`; codes with
  leading zeros (ZIP) stay text.
- Descriptions and comments state what the data is, not what is planned.
- Writing style, everywhere in the repo: no em dashes or en dashes.
