# health_analytics

A dbt project over synthetic electronic health record data: staged source
feeds, a dimensional model, a data-quality test suite, generated
documentation, and CI that runs the whole thing on every push to `main`
and every pull request.

The data is [Synthea](https://synthetichealth.github.io/synthea/), MITRE's
synthetic patient generator. It is entirely artificial. There is no PHI here
and no real person is represented.

The generated documentation, model lineage and test coverage included, is
published from this repository on every push to `main`:
**https://jaredf96.github.io/health-analytics/**

Every number below comes out of a `dbt build` of this repository. If a number
here and the build ever disagree, the build is right and this file is a bug.

## Run it

This builds on Python 3.12, pinned in `.python-version`. The pinned
dependencies need 3.10 or newer.

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

CI publishes that same site to GitHub Pages on every push to `main`.

## What the build produces

15 models and 202 tests, in under two seconds on a laptop:

```
Done. PASS=216 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=217
```

The one warning is expected and is explained under Data quality below.

**Staging**, 6 models, one per source feed. Each renames the all-text CSV
columns to snake_case and casts them, and does nothing else: no filtering, no
derived columns. Patients, encounters, conditions, organizations, providers,
payers.

**Marts**, 7 dimensions and 2 facts at two different grains. `fct_encounter`
is one row per encounter, 61,459 rows. `fct_condition` is one row per condition
recorded for a patient at an encounter, 38,094 rows. Each carries the grain of
its staging model and filters nothing.

The second fact is the shape of the star rather than an addition to it.
`dim_patient` and `dim_date` are conformed across both, which means a filter on
either one selects the same patients and the same days on both sides, so the
two facts can be summarized separately and the results lined up on those
attributes. Drilling across like that is the only safe way to combine them.
Joining the facts to each other instead fans an encounter out once per
condition and drops the 34,555 encounters that recorded none, so an encounter
measure summed through `fct_condition` is wrong in both directions at once.
`fct_condition` adds exactly one dimension of its own, `dim_condition`, and
references `fct_encounter` rather than re-describing the visit. It joins
`dim_date` twice, once for the start of the condition and once for its end,
which is the role-playing pattern rather than a second date table.

Conformance is an assertion, not a diagram, so a test makes it:
`tests/assert_condition_patient_matches_encounter_patient.sql` checks that the
patient a condition names and the patient its encounter names are the same
person. Both foreign keys can resolve while pointing at different people, which
is exactly what a `relationships` test cannot see.

The dimensions resolve real problems in the feed rather than renaming columns:

- `dim_encounter_type` picks one description per SNOMED code. The feed does
  not supply one: six codes carry several spellings, including case variants
  of the same words, so the model takes the spelling used on the most
  encounters and breaks ties on the text. Encounter class is not an attribute
  of the code, because five codes appear in more than one class, so class
  stays on the fact as a degenerate dimension.
- `dim_condition` picks one description per SNOMED code by the same rule, and
  carries the parenthetical semantic tag under the source's own name because
  the source is all it reflects: 95 of the 202 codes have no tag, and one
  arrives with the closing parenthesis missing. What it does show is worth
  knowing before reading anything else off this fact. 29,749 of the 38,094
  condition rows are SNOMED findings rather than disorders, and the most
  common code in the whole fact is `Full-time employment`. A count of
  conditions here is not a count of diagnoses.
- `dim_payer` sorts the ten payers into self pay, public and commercial.
  Synthea's self-pay stand-in, `NO_INSURANCE`, is the payer on 13,620 of
  61,459 encounters, more than any real plan, so leaving it uncategorized
  would inflate commercial volume by 41 percent.
- `dim_provider` drops the address columns, which repeated the employing
  organization's address rather than carrying a clinician's own. Geography
  belongs to `dim_organization`, once.
- `dim_date` is a spine anchored to the first and last encounter in the data,
  1912-09-26 to 2021-11-19. No model in this project reads the clock, so a
  rebuild produces the same numbers on any machine on any day.

Money reconciles exactly between `fct_encounter` and its staging model:
255,033,828.08 billed, 63,530,758.42 covered by payers, 191,503,069.66 not
covered by a payer. That residual is `uncovered_amount` rather than patient
responsibility: in a real revenue cycle most of it is the contractual
adjustment between charges and the negotiated rate, and Synthea carries neither
adjustments nor allowed amounts, so the two cannot be separated here.
Payer mix by encounter is 33,231 commercial, 14,608 public, 13,620 self pay.

## Data quality

202 tests: 188 generic and 14 singular.

The generic tests are 134 `not_null`, 21 `unique`, 19 `relationships` and 14
`accepted_values`. The relationships tests are real assertions rather than
aspirations: every foreign key in the project resolves with zero orphans, from
encounters to patients, organizations, providers and payers, from conditions to
patients and encounters, from providers to organizations, from the encounter
fact to each of its six dimensions, and from the condition fact to the patient,
condition and date dimensions and to the encounter fact itself.

The singular tests carry the assertions no generic test covers. Encounter and
condition periods do not end before they start. A payer never covers more than
the encounter was billed, so the uncovered residual is never negative. An
encounter reason arrives as a code and a label together or not at all. Neither
fact filters, which is checked by comparing each one row for row against its
staging model. The conditions feed has no key column, so one test asserts its
grain in staging and a second asserts the fact preserved it. The two facts
agree about which patient an encounter belongs to. And no combination of
columns in the marts recovers an age Safe Harbor hides, which is asserted
against the data rather than against the column names.

**One test warns, on purpose.** 165 of 61,459 encounters start after the
patient's recorded death date, one to fourteen days after, across 154
patients. It is an artifact of how Synthea generates a population. Nothing in
this project filters those rows out: dropping them would make the fact
disagree with its source for a reason no reader could see. Instead the test
asserts the rule at warn severity, so `dbt build` reports the count on every
run, prices the defect at 0.27 percent of encounters, and turns it into a
failure the moment it grows. See `docs/DECISIONS.md` section 15.

## Governance

`dim_patient` is de-identified to the HIPAA Safe Harbor standard. Names,
street address, city, county, coordinates and full dates stay in staging and
never reach it. Dates become years, and ZIP becomes its first three digits
with the seventeen prefixes HHS restricts replaced by `000`.

Ages over 89 are the part worth reading closely, because capping the age
column is not enough on its own. Safe Harbor aggregates everyone over 89 into
one category and removes the date elements, the year included, that would
reveal such an age. So `dim_patient` withholds `birth_year` and `death_year`
for those 35 patients rather than publishing them beside a capped age: keeping
the years would let one subtraction undo the cap, and joining a birth year to
a date on the fact would undo it for every encounter of that patient.
`patient_age_years` is capped at 90 on both facts to match.

A second fact is where a rule like this usually breaks, because the suppression
has to hold against dates the dimension has never seen. So it is computed from
every date the marts publish about a patient: their death, the start and the
end of every encounter, and the start and the end of every condition. Not one
per feed, because the obvious date is not always the latest one here. 165
encounters start and 168 end after the patient's recorded death, and a
condition can outlive the visit that recorded it by weeks. The test that reads
the data checks all of them, against the exact birth date in staging rather
than against year arithmetic, which is ambiguous by a year in both directions.
Widening the rule moved no patient into or out of the 90-or-older category, and
the highest age any published column now yields is 89. `docs/DECISIONS.md`
section 22.

The claim is scoped to one model. Both facts deliberately keep the dates of
care, exact timestamps on `fct_encounter` and days on `fct_condition`, because
a fact that cannot say when something happened is not much of a fact. The marts
layer as a whole is therefore not a Safe Harbor data set, and only `dim_patient`
claims to be.

The data is synthetic, so this protects nobody. That is the point: the rule is
the deliverable. Two tests enforce it, and the distinction between them is
the lesson.
`tests/assert_patient_dimension_excludes_direct_identifiers.sql` reads
`information_schema` and fails if a forbidden column reappears, but it only
knows column names. It could not see the age leak above, because `birth_year`
was never on its list.
`tests/assert_safe_harbor_age_over_89_is_suppressed.sql` reads the data
instead and asserts that no combination of columns recovers an age the rule
hides. A control that checks names is not a control that checks the rule.

Staging keeps the full record. Anything that genuinely needs a patient's exact
date of birth joins the staging model and inherits the responsibility for
doing so.

## Layout

```
models/staging/synthea/   one stg_synthea__<entity>.sql per source feed
models/marts/             dim_<entity>.sql and fct_<event>.sql
macros/                   shared SQL expressions, one macro per file
tests/                    singular tests, one assertion per file
scripts/fetch_synthea.py  checksum-pinned data fetch, standard library only
docs/DECISIONS.md         why the project is shaped the way it is
.github/workflows/        CI: dbt build on main and on every pull request
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
marts key on natural identifiers, why the second fact conforms to the first
one's dimensions instead of keying itself, why nothing reads the clock, and why
a known defect is warned rather than filtered. Read it before changing the
materialization, the sources, the dataset, or the identifier policy.
