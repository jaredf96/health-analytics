# Decisions

Why the project is shaped the way it is. One entry per decision, newest at the
bottom. Each entry says what was decided, what it was decided against, and what
would reopen it. Numbers come from the files and builds in this repo.

## 1. DuckDB for development and CI

**Decided 2026-09-02.** The dev and CI target is DuckDB through `dbt-duckdb`,
with the database as a single gitignored file.

**Why.** It is free, in-process, needs no credentials, and runs unchanged in a
GitHub Actions job, so the whole build is reproducible by anyone with Python.

**Against.** Snowflake, BigQuery, Databricks, and Redshift all need an account
and secrets in CI. A cloud target is planned as an addition once the model
layer is stable, not as a replacement: the same models will build on both, and
the README will only name a warehouse the repo has actually built on.

## 2. Repo-local `profiles.yml`

**Decided 2026-09-02.** The dbt profile lives in the repo root instead of
`~/.dbt/profiles.yml`.

**Why.** The DuckDB profile has no secrets, and a repo-local file means a fresh
clone builds with no machine setup. dbt checks the working directory for a
profile before falling back to `~/.dbt`.

**Consequence.** dbt only finds it when launched from the repo root. CI and the
README quickstart set `DBT_PROFILES_DIR` to the repo root so the invocation is
location-independent. A cloud target will read its credentials through
`env_var()` in this same file.

## 3. Dataset: the Synthea nov2021 sample

**Decided 2026-09-02, confirmed by a second-model review.** The source data is
`synthea_sample_data_csv_nov2021.zip` from MITRE's Synthea sample-data site,
pinned by URL and SHA-256 in `scripts/fetch_synthea.py`.

**Why Synthea at all.** It is entirely synthetic, so there is no PHI, while
still carrying the shape of a real EHR export: patients, encounters,
conditions, observations, procedures, medications, immunizations, providers,
organizations, payers, and claims.

**Why this archive.** Four archives were downloaded and measured on
2026-09-02:

| Archive | Size | Patients | CSV files | Claims and claim transactions | Patient schema |
|---|---|---|---|---|---|
| `synthea_sample_data_csv_nov2021.zip` | 59 MB | 1,163 | 18 | yes | 2021: no INCOME, FIPS, or MIDDLE columns |
| `downloads/latest/synthea_sample_data_csv_latest.zip` | 6 MB | 108 | 18 | yes | current |
| `synthea_sample_data_csv_apr2020.zip` | 9 MB | 1,171 | 16 | no | 2020 |
| `10k_synthea_covid19_csv.zip` | 57 MB | 12,352 | 15 | no | 2020 |

nov2021 is the only dated, stably named archive that includes the financial
files. Its largest tables are claims transactions (711,238 rows), observations
(531,144), imaging studies (151,637), claims (117,889), procedures (83,823),
and encounters (61,459), which is enough to model real grains and run
non-trivial test suites while a full build still takes seconds on a laptop.

**Against.** The `latest` archive has the newest patient schema but only 108
patients, and its name implies upstream may regenerate it, which would break a
checksum pin. `apr2020` has no claims. The 10k COVID-19 archive has no claims
and ships an HTML report and macOS resource-fork files inside the zip.
Generating a population locally with Synthea (Java) was rejected for now: it
makes reproducibility depend on a pinned Synthea release and seed plus minutes
of generation in CI.

**What would reopen it.** A need for more patients or the current schema. The
path then is to generate once from a pinned Synthea release and seed, publish
the archive as a checksum-pinned GitHub Release asset, and point the fetch
script at it.

## 4. Sources are CSVs read in place, typed in staging

**Decided 2026-09-02.** Sources are declared with dbt-duckdb's
`external_location` as `read_csv('data/raw/synthea/{name}.csv', header=true,
all_varchar=true)`. No load step and no seeds.

**Why.** Reading in place keeps the raw layer raw: the CSV is the source of
truth and dbt owns everything after it. `all_varchar=true` disables DuckDB's
type sniffing so every cast is written down in the staging model, where it is
visible, tested, and documented. Sniffing would have turned ZIP codes with
leading zeros into integers.

**Consequence.** Staging models carry explicit casts. Money columns arrive with
floating-point noise (up to 18 decimals) and are cast to `decimal(18, 2)`,
which DuckDB rounds to cents.

## 5. Staging materialized as tables, not views

**Decided 2026-09-02, confirmed by a second-model review.** The `staging`
folder is configured `+materialized: table`.

**Why.** dbt convention makes staging views because in a warehouse they sit on
raw tables and cost nothing. Here the sources are files. A view over
`read_csv` re-parses the file on every query, so each of the ten to fifteen
tests on a model would re-read up to 310 MB, and the persisted view carries a
relative path that only resolves when the database file is opened from the
repo root. As tables, each CSV is parsed once per build, tests hit tables, and
the database file is self-contained.

**What would reopen it.** A cloud target with loaded raw tables. At that point
the config becomes target-conditional (tables on DuckDB, views elsewhere). It
is not written that way now because nothing would exercise the other branch.

## 6. Direct identifiers excluded in staging

**Decided 2026-09-02.** `stg_synthea__patients` does not select SSN, DRIVERS,
or PASSPORT. It keeps names, full birth and death dates, street address, and
coordinates.

**Why.** No downstream model needs the three excluded columns; the patient key
is the Synthea UUID. A real EHR feed would leave them out at ingest under the
HIPAA minimum-necessary rule, and a staging layer is the right place to make
that visible. The columns that are kept are needed for age and geography in
the patient dimension. How they are exposed downstream (age bands, ZIP3,
masking) is a mart-level decision and will be recorded with the marts.

## 7. Fetch script design

**Decided 2026-09-02.** `scripts/fetch_synthea.py` uses only the standard
library. It downloads to a work directory, checks the byte count against
`Content-Length` with three attempts, verifies the SHA-256, extracts, and only
then swaps the new files into `data/raw/synthea/`. A manifest records the
archive hash and the size of every extracted file, so a missing or truncated
CSV triggers a refetch and a matching manifest makes re-runs a no-op.

**Why.** A checksum mismatch and a truncated download are different problems
and must be reported differently. Existing data must survive a failed run. CI
must need nothing beyond Python.

## 8. Claims data profile

**Recorded 2026-09-02**, from the nov2021 archive, to inform the claims models.
Not a decision, but the facts the next decisions will rest on.

- `claims.Id` and `claims_transactions.ID` are unique and never null.
- Every foreign key from claims and claim transactions to patients,
  encounters, and providers resolves; zero orphans. Every encounter has at
  least one claim, and there are several claims per encounter, split by claim
  type.
- Transaction rows are one per line, typed CHARGE, PAYMENT, TRANSFERIN, or
  TRANSFEROUT. PAYMENT rows carry their amount in `PAYMENTS`, not `AMOUNT`;
  TRANSFEROUT rows carry it in `TRANSFERS`.
- 22 percent of claims have `PRIMARYPATIENTINSURANCEID = '0'`, Synthea's
  self-pay sentinel. `encounters.PAYER` resolves to a payer for every row and
  is the reliable payer reference.
- The sum of CHARGE lines does not reconcile to `encounters.TOTAL_CLAIM_COST`
  (206.9 million versus 255.0 million). No model may claim the two agree.

## 9. Encounter timestamps stay UTC

**Decided 2026-09-03.** `encounters.START` and `STOP` arrive as ISO 8601 with
a `Z` suffix (`2019-02-17T05:07:38Z`). `stg_synthea__encounters` casts them to
`timestamp`, which keeps the UTC wall clock, rather than to `timestamptz`.

**Why.** A `timestamptz` cast in DuckDB resolves the value against the session
time zone, so the same CSV builds different timestamps on a laptop in New York
and in a CI runner on UTC. Every number this repo publishes has to be
reproducible from a `dbt build`, so a machine-dependent cast is disqualifying.
Casting to `timestamp` records exactly what the file says.

**Consequence.** Downstream models read these as UTC. Anything that needs local
clock time, such as an hour-of-day admission pattern, has to convert
explicitly and say which zone it converted to. The column descriptions say UTC
so nobody has to infer it.

## 10. The conditions grain is asserted, not keyed

**Decided 2026-09-03.** `conditions.csv` has no key column. Staging does not
add a surrogate key; instead `tests/assert_condition_grain_is_unique.sql`
asserts that `patient_id`, `encounter_id` and `condition_code` identify a row.
It holds across all 38,094 rows.

**Why.** Staging renames and casts and does nothing else, so a hashed key would
be the first derived column in the layer and would set a precedent the other
models do not follow. The grain still has to be guaranteed, because every
downstream join depends on it, and a singular test guarantees it without
inventing data. A surrogate key also needs a hashing macro, which means either
a `dbt_utils` dependency and a `dbt deps` step in CI or a hand-rolled macro
that has to be portable across warehouses.

**What would reopen it.** A mart that needs a stable single-column key for the
condition grain. The key belongs in that mart, where the hash function and the
column order are visible next to the model that depends on them.

## 11. Clinical reference profile

**Recorded 2026-09-03**, from the nov2021 archive, to inform the dimensional
models. Not a decision, but facts the next decisions rest on.

- Every foreign key resolves. Encounters to patients, organizations, providers
  and payers, conditions to patients and encounters, and providers to
  organizations are all zero orphans, so the relationships tests are real
  assertions rather than aspirations.
- A SNOMED code does not determine its description. Six encounter codes and
  two condition codes carry more than one spelling, including case variants:
  `185347001` appears as `Encounter for problem`, `Encounter for problem
  (procedure)` and `Encounter for Problem`. A code dimension has to be keyed on
  the code alone and pick one label deliberately.
- `encounters.PAYER_COVERAGE` is never greater than `TOTAL_CLAIM_COST`, and no
  money column in encounters is negative.
- `BASE_ENCOUNTER_COST` takes exactly two values, 129.16 and 77.49. It is a
  Synthea constant, not a modelled price.
- `REASONCODE` is null on 45,502 of 61,459 encounters, and `REASONDESCRIPTION`
  is null on exactly the same rows.
- Encounter class splits 24,038 wellness, 20,124 ambulatory, 10,837 outpatient,
  2,564 urgent care, 2,168 emergency, 1,728 inpatient.
- NO_INSURANCE is the payer on 13,620 of 61,459 encounters, more than any real
  plan. Any payer mix that does not name it separately will mislead.
- Organization and provider ZIPs arrive in three shapes: ZIP+4, five digits,
  and four digits where a leading zero was dropped. Patient ZIPs are five
  digits or null. All ZIPs stay text; normalizing is a mart decision.
- `organizations.REVENUE` is 0.00 on every row and `STATE` is MA on every row
  of both organizations and providers. Neither column carries information in
  this sample.
- `providers` addresses repeat the employing organization's address, so a
  provider dimension adds nothing geographic that the organization does not
  already have.
