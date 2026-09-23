# health_analytics

[![build](https://github.com/jaredf96/health-analytics/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/jaredf96/health-analytics/actions/workflows/build.yml?query=branch%3Amain)
[![license](https://img.shields.io/github/license/jaredf96/health-analytics)](LICENSE)

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

15 models and 206 tests, in under two seconds on a laptop:

```
Done. PASS=219 WARN=2 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=221
```

Both warnings are expected and are explained under Data quality below.

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
- `dim_payer` groups the ten payers twice, at two widths.
  `payer_financial_class` names the program that pays and keeps Medicare,
  Medicaid and Dual Eligible apart, because those three pay at different
  rates and are separate lines on a payer-mix report. `payer_category` rolls
  them into public for the reads that want the sector. The rollup is derived
  from the class rather than mapped from the payer name a second time, so the
  two cannot disagree. Synthea's self-pay stand-in, `NO_INSURANCE`, is the
  payer on 13,620 of 61,459 encounters, more than any real plan, so leaving
  it unclassed would inflate commercial volume by 41 percent.
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
Payer mix by encounter is 33,231 commercial, 13,620 self pay, 8,482 Medicare,
5,283 Medicaid and 843 dual eligible. Those last three are the 14,608
encounters `payer_category` reports as public, and Medicare alone is 58
percent of them.

## Data quality

206 tests: 188 generic and 18 singular.

The generic tests are 133 `not_null`, 21 `unique`, 19 `relationships` and 15
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
agree about which patient an encounter belongs to. Length of stay is
populated on exactly the inpatient encounters and null everywhere else, so the
scoping rule is an assertion rather than a convention. And neither a birth year
the dimension publishes nor an age either fact publishes, set beside a date the
facts publish, reveals an age Safe Harbor hides. That is asserted against the
data rather than against the column names, and Governance below says what it
leaves open.

**Two tests warn, on purpose.** 165 of 61,459 encounters start after the
patient's recorded death date, one to fourteen days after, across 154
patients. And 1 of the 1,728 inpatient stays runs 4,969 days, admitted 1996 and
discharged 2010. Both are artifacts of how Synthea generates a population.
Nothing in this project filters those rows out: dropping them would make the
fact disagree with its source for a reason no reader could see. Instead each
test reports its count on every run, pricing the first defect at 0.27 percent
of encounters and the second at 1 stay in 1,728.

Each test pins the count it tolerates and fails above it, `warn_if = '> 0'` with
`error_if = '> 165'` and `> 1` respectively, so a 166th post-death encounter or
a second year-long stay is an error and breaks CI. A bare `severity: warn` warns
at any count and would not, which is what these tests carried until a review
caught it. See `docs/DECISIONS.md` sections 15, 25 and 26.

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
`patient_age_years` is withheld entirely on both facts for those 35 patients,
rather than capped. A cap is not enough: it leaves the exact ages below 90 in
place, and an exact age beside an exact service date bounds a birth year that a
later date turns back into an age. That recovered an age for all 35 of them,
to a maximum of 109, until it was closed. `docs/DECISIONS.md` section 27.

A second fact is where a rule like this usually breaks, because the suppression
has to hold against dates the dimension has never seen. So it is computed from
every date the marts publish about a patient: their death, the start and the
end of every encounter, and the start and the end of every condition. Not one
per feed, because the obvious date is not always the latest one here. 165
encounters start and 168 end after the patient's recorded death, and a
condition can outlive the visit that recorded it by weeks. The test that reads
the data checks all of them, against the exact birth date in staging rather
than against year arithmetic, which is ambiguous by a year in both directions.
Widening the rule moved no patient into or out of the 90-or-older category.
`docs/DECISIONS.md` section 22.

The claim is scoped to one model. Both facts deliberately keep the dates of
care, exact timestamps on `fct_encounter` and days on `fct_condition`, because
a fact that cannot say when something happened is not much of a fact. The marts
layer as a whole is therefore not a Safe Harbor data set, and only `dim_patient`
claims to be.

The data is synthetic, so this protects nobody. That is the point: the rule is
the deliverable. Two tests enforce it on `dim_patient`, and the distinction
between them is the lesson.
`tests/assert_patient_dimension_excludes_direct_identifiers.sql` reads
`information_schema` and fails if a forbidden column reappears, but it only
knows column names. It could not see the age leak above, because `birth_year`
was never on its list.
`tests/assert_safe_harbor_age_over_89_is_suppressed.sql` reads the data
instead, and asserts that no birth year the dimension publishes, set beside any
date either fact publishes, lands on an age the rule hides. A control that
checks names is not a control that checks the rule.

The ages on the facts need a test of their own, because an age beside a date
bounds a birth year with no dimension column involved.
`tests/assert_fact_age_and_date_do_not_imply_over_89.sql` does the arithmetic an
attacker would do, taking each published age as a bound on a birth year and
checking it against that patient's latest published date.

What the tests that read the data do not prove is worth saying plainly, because
the scoping above is what carries it rather than any test. The facts publish
exact service dates, so a patient's own span of care can bound an age with no
dimension column involved at all: 10 of the 35 have published events more than
89 years apart, and the widest span is 108 years. No test here proves that no
combination of published columns recovers a hidden age, and while the facts
keep exact dates on purpose, none could. That is why Safe Harbor is claimed for
`dim_patient` and is not claimed for the marts.

Staging keeps the full record. Anything that genuinely needs a patient's exact
date of birth joins the staging model and inherits the responsibility for
doing so.

## Layout

```
models/staging/synthea/   one stg_synthea__<entity>.sql per source feed
models/marts/             dim_<entity>.sql and fct_<event>.sql
models/overview.md        the landing page of the generated docs site
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

## Author

Jared Fulk, [@jaredf96](https://github.com/jaredf96). Released under the
[MIT License](LICENSE).
