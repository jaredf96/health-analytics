# health_analytics

A dbt project over synthetic electronic health record data: staged source
feeds, a dimensional model, a data-quality test suite, generated
documentation, and CI that runs the whole thing on every push.

The data is [Synthea](https://synthetichealth.github.io/synthea/), MITRE's
synthetic patient generator. It is entirely artificial. There is no PHI here
and no real person is represented.

Every number below comes out of a `dbt build` of this repository. If a number
here and the build ever disagree, the build is right and this file is a bug.

## Run it

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python scripts/fetch_synthea.py
.venv/bin/dbt build
```

The fetch script downloads one checksum-pinned archive and lands 18 CSVs in
`data/raw/synthea/` (about 565 MB, gitignored). dbt-duckdb reads them in
place, so there is no load step and no credentials. Run dbt from the repo
root, because `profiles.yml` is repo-local; from anywhere else set
`DBT_PROFILES_DIR` to the repo root.

To read the generated documentation locally:

```bash
.venv/bin/dbt docs generate && .venv/bin/dbt docs serve
```

CI publishes the same site to GitHub Pages on every push to `main`,
once the repository is public. Pages is not available on a private
repository on the Free plan, so the publishing job is gated on that and
turns itself on when the repository is made public.

## What the build produces

13 models and 180 tests, in about 1.5 seconds on a laptop:

```
Done. PASS=192 WARN=1 ERROR=0 SKIP=0
```

The one warning is expected and is explained under Data quality below.

**Staging**, 6 models, one per source feed. Each renames the all-text CSV
columns to snake_case and casts them, and does nothing else: no filtering, no
derived columns. Patients, encounters, conditions, organizations, providers,
payers.

**Marts**, 6 dimensions and 1 fact. `fct_encounter` is one row per encounter,
61,459 rows, the same grain as its staging model, filtering nothing. Its
foreign keys reach `dim_patient`, `dim_provider`, `dim_organization`,
`dim_payer`, `dim_encounter_type` and `dim_date`.

The dimensions resolve real problems in the feed rather than renaming columns:

- `dim_encounter_type` picks one description per SNOMED code. The feed does
  not supply one: six codes carry several spellings, including case variants
  of the same words, so the model takes the spelling used on the most
  encounters and breaks ties on the text. Encounter class is not an attribute
  of the code, because five codes appear in more than one class, so class
  stays on the fact as a degenerate dimension.
- `dim_payer` sorts the ten payers into self pay, public and commercial.
  Synthea's self-pay stand-in, `NO_INSURANCE`, is the payer on 13,620 of
  61,459 encounters, more than any real plan, so leaving it uncategorised
  would inflate commercial volume by 41 percent.
- `dim_provider` drops the address columns, which repeated the employing
  organization's address rather than carrying a clinician's own. Geography
  belongs to `dim_organization`, once.
- `dim_date` is a spine anchored to the first and last encounter in the data,
  1912-09-26 to 2021-11-19. No model in this project reads the clock, so a
  rebuild produces the same numbers on any machine on any day.

Money reconciles exactly between the fact and its staging model: 255,033,828.08
billed, 63,530,758.42 covered by payers, 191,503,069.66 left with patients.
Payer mix by encounter is 33,231 commercial, 14,608 public, 13,620 self pay.

## Data quality

180 tests: 170 generic and 10 singular.

The generic tests are 122 `not_null`, 20 `unique`, 14 `relationships` and 14
`accepted_values`. The relationships tests are real assertions rather than
aspirations: every foreign key in the project resolves with zero orphans, from
encounters to patients, organizations, providers and payers, from conditions
to patients and encounters, from providers to organizations, and from the fact
to each of its six dimensions.

The singular tests carry the assertions no generic test covers. Encounter and
condition periods do not end before they start. A payer never covers more than
the encounter was billed. Patient responsibility is never negative. An
encounter reason arrives as a code and a label together or not at all. The
conditions feed has no key column, so a test asserts its grain instead.

**One test warns, on purpose.** 165 of 61,459 encounters start after the
patient's recorded death date, three to fourteen days after, across 154
patients. It is an artifact of how Synthea generates a population. Nothing in
this project filters those rows out: dropping them would make the fact
disagree with its source for a reason no reader could see. Instead the test
asserts the rule at warn severity, so `dbt build` reports the count on every
run, prices the defect at 0.27 percent of encounters, and turns it into a
failure the moment it grows. See `docs/DECISIONS.md` section 15.

## Governance

`dim_patient` is de-identified to the HIPAA Safe Harbor standard. Names,
street address, city, county, coordinates and full dates stay in staging and
never reach the mart. Dates become years, ZIP becomes its first three digits
with the seventeen prefixes HHS restricts replaced by `000`, and any age over
89 is reported as 90. `fct_encounter.patient_age_years` is capped the same
way, so the fact cannot be used to recover an age the dimension hides.

The data is synthetic, so this protects nobody. That is the point: the rule is
the deliverable. `tests/assert_patient_dimension_excludes_direct_identifiers.sql`
reads `information_schema` and fails the build if a forbidden column
reappears, so the policy is enforced by CI rather than by trust.

Staging keeps the full record. Anything that genuinely needs a patient's exact
date of birth joins the staging model and inherits the responsibility for
doing so.

## Layout

```
models/staging/synthea/   one stg_synthea__<entity>.sql per source feed
models/marts/             dim_<entity>.sql and fct_<event>.sql
tests/                    singular tests, one assertion per file
scripts/fetch_synthea.py  checksum-pinned data fetch, standard library only
docs/DECISIONS.md         why the project is shaped the way it is
.github/workflows/        CI: dbt build on every push and pull request
```

## Warehouse

The target is DuckDB, as a single local file. It needs no account and no
secrets, so a fresh clone builds and CI runs the identical command.

A cloud warehouse target is planned and is deliberately not claimed yet. The
sources here are CSV files read in place, which no cloud warehouse can do
without an ingestion step, so a real Snowflake or BigQuery target means
designing that step rather than adding a second block to `profiles.yml`.
This README will name a warehouse when the repository has actually built on
it, and not before.

## Decisions

`docs/DECISIONS.md` records every decision behind the project, each with what
it was decided against and what would reopen it: why this Synthea archive,
why sources are read in place, why staging is materialized as tables, why the
marts key on natural identifiers, why nothing reads the clock, and why a known
defect is warned rather than filtered. Read it before changing the
materialization, the sources, the dataset, or the identifier policy.
