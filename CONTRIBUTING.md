# Contributing

How this project is put together, and the rules a change has to keep.

## What this is

A dbt analytics-engineering project over synthetic EHR data from Synthea. It
demonstrates, with runnable evidence, the core of an analytics engineer's job
in healthcare: staging raw feeds, dimensional models, data-quality tests,
documentation, and CI. It runs on DuckDB. A number stated in the README or the
docs is a query over the warehouse a `dbt build` of this repo produces, or over
the source files it reads, unless it says where else it comes from, and then it
has to say: `docs/DECISIONS.md` section 29.

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
- Run dbt from the repo root. dbt finds the project and the repo-local
  `profiles.yml` in the working directory, and the profile's DuckDB path and
  the sources' CSV paths are relative to it. `DBT_PROFILES_DIR` finds the
  profile from elsewhere and nothing else, so it does not make another
  directory work.
- Run `dbt build --no-partial-parse` before committing yml changes, so
  deprecation warnings surface.
- Two warnings are expected and correct: the post-death encounter test,
  `docs/DECISIONS.md` section 15, and the inpatient length-of-stay
  plausibility test, section 25. A third warning is a regression.
- Both pin the count they tolerate and error above it, so a growing defect
  fails rather than warning louder. If you change one legitimately, move its
  `error_if` bound in the same commit. Section 26 says why a bare
  `severity: warn` is not enough.

## Layout

- `models/staging/<source>/`: `_<source>__sources.yml`,
  `_<source>__models.yml`, and one `stg_<source>__<entity>.sql` per entity
  the marts read. A feed declared only to be profiled has no staging model.
- `models/marts/`: `_marts__models.yml`, one `dim_<entity>.sql` per dimension
  and one `fct_<event>.sql` per fact. Marts are where derived columns and
  business rules live, and where the Safe Harbor rules are applied.
- `models/overview.md`: the landing page of the generated docs site, as the
  `__overview__` docs block. Keep counts out of it; no build checks them there.
- `macros/`: shared SQL expressions, one macro per file. A rule two models
  need lives here rather than in both.
- `tests/`: singular tests, one assertion per file, named `assert_<what>.sql`.
- `analyses/`: profiles of source feeds no model reads, which the decision log
  cites. Each is run as `dbt show --select <name> --limit 50 --output json`,
  asserts nothing, and runs in CI after the build so it stays runnable.
  `docs/DECISIONS.md` section 29.
- `scripts/`: data fetching. Standard library only, so CI needs nothing extra.
- `docs/DECISIONS.md`: why things are the way they are. Read it before
  changing materialization, sources, the dataset, or the identifier policy.

## Conventions

- Sources are CSV files read in place by dbt-duckdb, every column as text.
  Staging does all renaming and casting and nothing else: no filtering, no
  derived columns. Every cast in a staging model is deliberate. An analysis
  that reads a feed with no staging model casts what it needs itself.
- Staging is materialized as tables on DuckDB. See `docs/DECISIONS.md`.
- Marts key on the natural identifiers the feed supplies. Most are Synthea
  UUIDs; `dim_date` keys on `date_id`, the day as a `YYYYMMDD` integer, and
  `dim_encounter_type` and `dim_condition` on the SNOMED CT code. No hashed
  surrogate keys. Where the feed supplies none, the grain stays composite and
  a singular test asserts it: `fct_condition` is keyed by `patient_id`,
  `encounter_id` and `condition_code` together. `docs/DECISIONS.md` sections
  10 and 21.
- No model reads the clock. `current_date` and `now()` are banned, because a
  `dbt build` has to produce the same numbers on any machine on any day.
- `dim_patient` applies the HIPAA Safe Harbor rules for names, geography,
  dates and ages over 89, and three tests enforce them, one on the column list
  and two on the data. It is not a Safe Harbor data set, because its key is
  the source system's patient identifier, so do not describe it as one
  anywhere. Read `docs/DECISIONS.md` sections 12, 19, 22, 27 and 28 before
  adding a column to it or an age to a fact. Section 19 is there because the
  first version of that rule did not hold, section 27 because the facts could
  go around it, and section 28 because the claim never covered the key. A new
  fact that publishes a date against `patient_id` has to be added to the
  `published_dates` union in `dim_patient`, to the clauses in
  `tests/assert_safe_harbor_age_over_89_is_suppressed.sql`, and to the
  `published_dates` union in
  `tests/assert_fact_age_and_date_do_not_imply_over_89.sql`; the age
  suppression is computed from every date the marts publish, not from the
  encounter feed alone. A fact that also publishes an age withholds it for
  the patients `dim_patient.is_age_90_or_older` flags, and joins
  `published_ages` in that test and `fact_rows` in
  `tests/assert_fact_age_is_withheld_for_the_protected_cohort.sql`.
- A column is named for what it measures, not for what it was meant to
  measure. `docs/DECISIONS.md` section 20 is a list of four times that went
  wrong here.
- Generic tests use `data_tests:` with parameters nested under `arguments:`.
- A plain YAML scalar cannot contain a colon followed by a space, so a
  `description:` that needs one has to be a `>` block. dbt reports the failure
  as a parsing error on the yml line, not as a YAML error, which sends you
  looking in the wrong place.
- Column names are snake_case. Keys end in `_id`, dates in `_date`, timestamps
  in `_at`. The exception is a key that is a SNOMED CT code:
  `dim_encounter_type` and `dim_condition` key on `encounter_code` and
  `condition_code`, and the facts' foreign keys keep those names, because the
  value is a code in a published terminology and `_id` would read as a key the
  feed assigned. Money is `decimal(18, 2)`; coordinates are `double`; codes
  with leading zeros (ZIP) stay text.
- Descriptions and comments state what the data is, not what is planned.
- Writing style, everywhere in the repo: no em dashes or en dashes.
