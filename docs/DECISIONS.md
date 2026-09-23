# Decisions

Why the project is shaped the way it is. One entry per decision, newest at the
bottom; an entry marked Recorded rather than Decided is a profile of the data
that later decisions rest on. Most entries say what was decided against or what
would reopen it, and some say both. Numbers come from the files and builds in
this repo.

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

**Consequence.** dbt only finds it when launched from the repo root. CI sets
`DBT_PROFILES_DIR` to the repo root so the invocation there is
location-independent, and the README tells a reader to run from the root or set
the same variable. A cloud target will read its credentials through
`env_var()` in this same file.

## 3. Dataset: the Synthea nov2021 sample

**Decided 2026-09-02.** The source data is
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

**Decided 2026-09-02.** The `staging`
folder is configured `+materialized: table`.

**Why.** dbt convention makes staging views because in a warehouse they sit on
raw tables and cost nothing. Here the sources are files. A view over
`read_csv` re-parses the file on every query, so each of the eight to
twenty-four tests on a staging model would re-read the whole CSV: 19 MB for
encounters today, and 310 MB for the claims transactions file the same archive
ships. The persisted view also carries a relative path that only resolves when
the database file is opened from the repo root. As tables, each CSV is parsed once per build, tests hit tables, and
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
  Synthea constant, not a modeled price.
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

## 12. Marts are de-identified to HIPAA Safe Harbor

**Decided 2026-09-03**, settling the question section 6 deferred. `dim_patient`
carries no name, no street address, no city or county, no coordinates and no
full dates. Dates are reduced to the year and ZIP to its first three digits
with the seventeen prefixes HHS restricts replaced by `000`. Ages over 89 are
aggregated into a single category and the year elements that would reveal such
an age are withheld with them; section 19 records why capping the age column
alone was not enough, and what it took to find that out.

**Scope.** The rule is applied to `dim_patient` and claimed for `dim_patient`.
`fct_encounter` keeps exact service timestamps on purpose, so the marts layer
as a whole is not a Safe Harbor data set. Section 19 covers that too.

**Why.** The data is synthetic, so this protects nobody. That is the point: the
rule is the deliverable. A staging layer that holds the full record and a mart
layer that holds a de-identified one is how a real health system separates the
restricted feed from the broadly readable analytics product, and writing the
rule in one model where it can be read and tested is the difference between
governance and an assertion that governance happened.
`tests/assert_patient_dimension_excludes_direct_identifiers.sql` reads
`information_schema` and fails if any forbidden column reappears, so a later
edit that quietly adds one back breaks the build rather than the policy.

**Against.** City-level and street-level analysis are gone, and age is coarse
above 89. Keeping the identifiers and de-identifying only at the consumer was
rejected: it puts the rule somewhere no test can see it.

**Consequence.** Safe Harbor governs patient data, not a directory of care
organizations, so `dim_organization` keeps its full address and coordinates.
Anything that genuinely needs a patient's full date or street joins the staging
model and inherits the responsibility for doing so.

**Amended 2026-09-23.** The heading and the scope above claim `dim_patient` as a
Safe Harbor data set, and it was not one when they were written. Its key,
`patient_id`, is the source system's own patient identifier, which the rule
removes. The dimension applies the rules for names, geography, dates and ages
over 89, and that is what the project claims now. The test named above is now
`tests/assert_patient_dimension_excludes_name_place_and_date_columns.sql`, for
what it checks. Section 28 records why the key stays and why the test was
renamed.

**What would reopen it.** A mart that needs finer geography or exact ages. The
path is a second, explicitly restricted patient dimension, not loosening this
one.

## 13. Marts key on the natural Synthea identifiers

**Decided 2026-09-03.** The dimensions key on the Synthea UUIDs that arrive in
the feed. No hashed surrogate keys. Two dimensions key on something other than
a UUID, because the feed supplies none for them: `dim_date` on `date_id`, the
day as a `YYYYMMDD` integer, and `dim_encounter_type` on the SNOMED CT code.

**Why.** The UUIDs are already stable, globally unique, and non-null on every
row, and every relationship test resolves against them. A hash would add a
column that carries no information the UUID does not, and generating one needs
either a `dbt_utils` dependency and a `dbt deps` step in CI or a hand-rolled
macro. `dim_date` is keyed on an integer instead because a date spine has no
natural identifier and `YYYYMMDD` is the conventional one.

**What would reopen it.** A second source system with its own patient
identifiers. Conforming two systems onto one patient dimension is exactly the
problem a surrogate key exists to solve, and that is when to add one.

**Extended 2026-09-04.** `dim_condition` is a third dimension keyed on
something other than a UUID, on the SNOMED CT code, for the same reason
`dim_encounter_type` is. `fct_condition` has no key column at all, and section
21 records why none was invented for it.

**Extended 2026-09-23.** Keying `dim_patient` on the source system's patient
identifier is also why it applies Safe Harbor's rules without being a Safe
Harbor data set. Section 28 records that consequence and why the key stays.

## 14. Nothing reads the clock

**Decided 2026-09-03.** No model calls `current_date`, `now()` or any equivalent.
`dim_date` spans the first encounter in the data to the last, 1912-09-26 to
2021-11-19, and ages are computed against a date the data supplies rather than
against today.

**Why.** Every number the README states has to be reproducible from a `dbt
build`. A model that reads the clock produces different numbers tomorrow, which
makes the README wrong on a schedule and makes a CI run that fails today
impossible to distinguish from one that failed because of a change.

**Consequence.** There is no "current age" anywhere. Age exists at an event, as
`fct_encounter.patient_age_years`, and at death, as
`dim_patient.age_at_death_years`. A dashboard that wants a current age computes
it at query time, where the reader can see the clock being read.

## 15. A known defect is warned, not filtered

**Decided 2026-09-03.** 165 of 61,459 encounters start after the patient's
recorded death date, one to fourteen days after, across 154 patients. Nothing
filters them. `tests/assert_encounter_not_after_patient_death.sql` asserts the
rule and warns at the 165 that exist rather than failing, so `dbt build` reports
the count on every run and completes. It warns above 0 and errors above 165; the
amendment below says why it is written that way rather than as a bare
`severity: warn`.

**Why.** Silently dropping the rows would make the fact disagree with staging
for a reason no reader could see, and section 4 of this log makes staging the
place where the feed is reproduced faithfully. Turning the test off would hide a
real defect. Warning states the defect in the build output, prices it at 0.27
percent of encounters, and turns it into a failure the moment it grows.

**Consequence.** `dbt build` on this repo ends `WARN=2`. This test is one of
the two, and section 25 is the other; both are expected. CI treats warnings as
success and errors as failure, so a genuine regression still breaks the build.

**Amended 2026-09-10.** The claim above, that the defect becomes a failure the
moment it grows, was not enforced when it was written. Section 26 says what was
wrong and what the test carries now.

**What would reopen it.** A mart whose question the defect actually distorts,
such as a mortality or end-of-life measure. That mart excludes the rows itself
and says so, rather than the fact excluding them for everybody.

## 16. Provider specialty does not reach the fact

**Recorded 2026-09-03**, found by querying the built star schema rather than by
profiling the CSVs, which is why it is here and not in section 11.

`encounters.PROVIDER` only ever names a GENERAL PRACTICE clinician. Of the
5,056 rows in `dim_provider`, 1,123 are referenced by `fct_encounter`, and of
the 63 specialties, exactly one is. The other 62 exist in the provider
directory and nowhere else. Organizations do not have this problem: 1,122 of
1,127 are referenced.

**Why it matters.** Grouping encounters by specialty returns a single row. Any
operational mart built on specialty mix, referral patterns, or care-team
composition would be measuring the generator rather than the data, and would
look broken to a reader who did not know. The provider dimension keeps the
column because it describes the directory faithfully, and both the model and
its documentation now say plainly that the fact cannot use it.

**What would reopen it.** A dataset whose encounters reference more than one
specialty. This is a property of the Synthea sample, not of the modeling.

## 17. The star schema came before the rest of the feeds

**Decided 2026-09-03.** With the clinical
core of staging green, the next work was the dimensional layer plus the things
that ship it: the test suite, the generated docs, and CI. Six more staging
models over claims, claims transactions, medications, procedures, observations
and immunizations were deliberately not built first.

**Why.** The unit that demonstrates an analytics project is a working vertical
slice, not a count of staged feeds. Encounters already carry
`total_claim_cost` and `payer_coverage`, so one fact covers the clinical and
the financial angle without touching the claims files, and the claims
reconciliation problem in section 8 stays out of the first model layer instead
of being its opening move. Models that nothing publishes are also models that
nothing proves, so the docs site and CI landed in the same step rather than
two steps later.

**Against.** Staging everything first gives a fuller lineage graph and a richer
fact when the marts do arrive. It also materializes a 711,238-row and a
531,144-row table that nothing reads yet, and it delays the layer that the
whole project exists to show.

**What would reopen it.** It is already reopened, in the ordinary way: the
financial feeds and a second fact at the condition grain are the next
candidates. This entry records why they were not first, not that they are
unwelcome.

**A related decision, same day.** The cloud warehouse target stays out of this
release for a sharper reason than section 1 gives. Sources here are CSV files
read in place, so there is no load step, and no cloud warehouse can execute
that source layer as written. A real Snowflake target means designing an
ingestion step and reopening section 4, not adding a second block to
`profiles.yml`. Configuration alone would demonstrate syntax rather than a
warehouse the repo has built on, which is exactly what the README refuses to
claim.

## 18. Age is completed years, not calendar-year boundaries

**Decided 2026-09-03**, after an audit run against the built warehouse before
the repository was made public.

Both age columns computed `date_diff('year', birth, event)`. DuckDB reads that
as the number of calendar-year boundaries crossed, which is not age: a birth on
1990-12-31 and a date of 2020-01-01 returns 30, where the completed age is 29.
It disagreed with the completed age on 29,831 of the 61,459 rows in
`fct_encounter` and on 94 of the 163 deceased patients in `dim_patient`, so the
difference was the common case rather than an edge case. Both columns were
documented as completed years throughout, so the code was wrong and the
descriptions were right.

`macros/completed_years.sql` now holds the expression and both models call it.
It subtracts a year when the birthday has not yet arrived in the event year,
agrees with DuckDB's two-argument `age()` on every row in the build, and reads
no clock, because the caller supplies both endpoints.

**Why a macro.** The rule was already duplicated across two models and would
have been duplicated again by any mart that reports an age. One definition that
both models call is the difference between a rule and a coincidence.

**Consequence.** `fct_encounter.patient_age_years` reports 90 on 1,901
encounters rather than 2,061. The 160 encounters that moved report 89, which
Safe Harbor permits, so nothing is disclosed that was hidden before. The old
expression could only ever overstate an age, so it over-applied the cap and
never under-applied it; `is_age_at_death_90_or_older` is true on the same 15
patients either way, and section 12 is unaffected.

**What would reopen it.** A warehouse whose `date_diff` already means completed
years. The macro would then be a wrapper over the native function rather than a
correction to it.

## 19. Safe Harbor removes the year elements, not just the age

**Decided 2026-09-03**, after an audit read the built marts the way a hospital
privacy analyst would rather than the way the author had.

`dim_patient` capped age at 90 and published `birth_year` and `death_year`
beside it. One subtraction undid the cap: 15 deceased patients resolved to
ages between 91 and 104, and `is_age_at_death_90_or_older` named exactly which
rows to try it on. A join from `fct_encounter` to `dim_patient.birth_year`
recovered ages up to 110 across the 1,901 encounters whose `patient_age_years`
read 90. Twenty living patients leaked the same way, because the old flag only
considered age at death and a patient with a 1917 birth year and encounters in
2021 is over 89 without having died.

45 CFR 164.514(b)(2)(i)(C) removes ages over 89 together with the elements of
dates, the year included, that are indicative of such an age, and allows them
to be aggregated into a single category instead. The cap was the aggregation;
the removal was missing.

**What changed.** `dim_patient` now computes the greatest age the data reveals
about a patient, at death if they died and at their last encounter otherwise,
and withholds `birth_year` and `death_year` for the 35 patients over 89.
`is_age_at_death_90_or_older` became `is_age_90_or_older`, because the old
name described a narrower question than the rule asks.

**Widened 2026-09-04.** "At their last encounter" was still one date per
patient, and a second fact publishes more. Section 22 replaces it with the
maximum over every date the marts publish, and that is the rule in force.

**Why the existing test did not catch it.**
`assert_patient_dimension_excludes_direct_identifiers.sql` reads
`information_schema` and compares column names against a list. `birth_year`
was not on the list and never would have been, because the column is permitted
and it was the combination that was not. A control that reads names cannot
assert a rule about values.
`assert_safe_harbor_age_over_89_is_suppressed.sql` reads the data and asserts
the closure directly, including the join back from the fact.

**Against.** Two dimension columns are now null for 35 patients, and any
analysis of the oldest cohort loses its birth year. That is what the rule
costs, and it is the rule's intent rather than a side effect.

**Consequence, and the honest version of the claim.** `fct_encounter` still
carries `started_at` and `stopped_at` at second precision, which Safe Harbor
would not permit for dates directly related to an individual. Stripping them
would leave a fact that cannot say when anything happened. So the fact keeps
them and the claim is scoped: `dim_patient` is a Safe Harbor data set, the
marts layer is not, and the README, the model description and this log all now
say so. The previous wording, that full dates never reach the mart, was not
true of the layer.

**Amended 2026-09-23.** "`dim_patient` is a Safe Harbor data set", above, was
not true when it was written, because the dimension's key is the source
system's own patient identifier. The scoping argument stands and the claim is
narrower than it said: the dimension applies Safe Harbor's rules and is not a
Safe Harbor data set either. The column test named above is now
`assert_patient_dimension_excludes_name_place_and_date_columns.sql`. Section
28.

**What would reopen it.** A requirement that the whole layer be releasable
under Safe Harbor. The path then is a separate, date-shifted fact, not
loosening this dimension.

## 20. Columns are named for what they measure

**Decided 2026-09-03**, from the same audit. Four names promised something the
values did not deliver.

- `patient_responsibility` was `total_claim_cost - payer_coverage` on every one
  of the 61,459 rows. In a real revenue cycle that residual is dominated by the
  contractual adjustment between charges and the negotiated rate, not by what a
  patient owes, and Synthea carries neither adjustments nor allowed amounts, so
  the two cannot be separated. It is `uncovered_amount` now, and the README no
  longer describes 191.5 million as money left with patients.
- `dim_organization.lifetime_encounter_count` and the provider equivalent are
  Synthea's own `UTILIZATION` figure, which counts every claim-bearing contact.
  They disagree with a count of `fct_encounter` rows on 1,020 of 1,122
  organizations and 1,021 of 1,123 providers, by as much as 28 times. Two
  columns in one star giving different answers to the same question is worse
  than either answer alone, so they carry the source's name now:
  `source_reported_utilization`.
- `dim_encounter_type.lifetime_encounter_count` was the opposite case. It is
  derived from the same feed as the fact and agrees with it on all 50 codes, so
  only the misleading `lifetime` prefix went and it is `encounter_count`.
- `dim_date` exposed `iso_week` with no ISO year. 2019-12-30 and 2020-01-01 are
  both ISO week 1 of 2020, so any weekly report grouping on `iso_week` and
  `calendar_year` split that week in two. `iso_year` and `iso_year_week` are
  there now.

**Why it is one entry.** These are the same mistake four times: a name that
describes what the author expected rather than what the query returns. The fix
is the same each time, and it is cheaper than the alternative, which is a
reader trusting the name.

## 21. The second fact conforms rather than keying itself

**Decided 2026-09-04.** `fct_condition` is one row per condition recorded for a
patient at an encounter, 38,094 rows over 202 SNOMED CT codes. It introduces
one dimension of its own, `dim_condition`, reuses `dim_patient` and `dim_date`
exactly as `fct_encounter` uses them, and references `fct_encounter` by
`encounter_id` rather than copying the encounter's organization, provider,
payer and class down onto the condition grain.

**Why.** A second fact earns its place by sharing dimensions with the first.
Two facts over private copies of the same dimensions are two projects in one
repository, and a patient count from one would not be comparable with a patient
count from the other. Copying the encounter's foreign keys down was the
alternative: it gives a wider table that answers the same questions, at the
price of a second set of values that has to be kept in step with the first.

**What conforming does and does not license.** A filter on `dim_patient` or
`dim_date` selects the same patients and the same days on either side, so the
two facts can be summarized separately and lined up on those attributes. That
is drilling across, and it is the only safe way to combine them. Joining the
facts to each other fans an encounter out once per condition and drops the
34,555 encounters that recorded none, so an encounter measure summed through
`fct_condition` is understated and overstated at the same time. Sharing a
dimension makes two answers comparable; it does not make one join correct.

**The grain, and the key that was not added.** The feed supplies no key column,
so the grain is `patient_id`, `encounter_id` and `condition_code` together,
which section 10 settled. Section 10 named a mart needing a stable
single-column key as what would reopen it. This mart does not need one. Every
join into the fact is on a dimension key rather than on the fact's own, and the
only thing lost is the `unique` generic test, which cannot run on three
columns; `tests/assert_condition_fact_grain_is_unique.sql` does that job on the
mart, next to `assert_condition_grain_is_unique.sql` which does it on staging.
Adding a hash would have introduced surrogate keys to a project that keys on
natural identifiers everywhere else, for one model, against section 13.

**dim_date is joined twice, in two roles.** A condition has a start and an end,
so the fact carries `start_date_id` and `stop_date_id`, both foreign keys into
`dim_date`, the second null on the 8,169 rows the feed leaves open. A second
date table would have been the same rows under a different name.

**Conformance is asserted, not drawn.** A condition row names a patient and an
encounter, and the encounter names a patient of its own. Both foreign keys can
resolve while pointing at different people, and two `relationships` tests would
pass on that.
`tests/assert_condition_patient_matches_encounter_patient.sql` asserts the two
facts agree; they do, on all 38,094 rows.

**A property of the feed the fact has to state.** The condition date and the
date of the encounter that recorded it are the same on 30,469 rows and differ
on the other 7,625, from 8 days before the encounter to 562 days after. A
report that dated conditions by their encounter would therefore be wrong on a
fifth of the fact, so `days_from_encounter_start` carries the difference rather
than leaving a reader to assume there is none.

**What would reopen it.** A model that has to join to the condition grain on
its own key, such as a status snapshot or a bridge to a code hierarchy. The
hashed key belongs in that model's fact, where the hash function and the column
order sit next to what depends on them.

## 22. The suppression rule reads every date the marts publish

**Decided 2026-09-04**, while adding the second fact, and corrected the same
day after a review pointed out that the first version of it did not do what its
own heading said.

Section 19 closed the Safe Harbor age leak by computing the greatest age this
data reveals about a patient and withholding the year elements above 89. That
computation read one date per patient: their death if they died, the start of
their last encounter otherwise. Two things are wrong with one date per patient
here, and the second fact made both of them matter.

**Death does not close the record.** Taking the death date and stopping there
skips everything the facts publish afterwards, and this feed publishes plenty:
165 encounters start and 168 end after the patient's recorded death, by up to
14 days. That is the defect section 15 warns about rather than filters, so the
suppression rule has to survive it rather than assume it away.

**The obvious date per feed is not the latest one.** An encounter's end is not
always within a day of its start: 27 of them end later than that patient's last
encounter began, and three run longer than a year. A condition outlives the
visit that recorded it, so 129 stop after the patient's last encounter, by up
to 69 days.

So `dim_patient` takes the maximum over every date the marts publish for a
patient: the death date, the start and the end of every encounter, and the
start and the end of every condition.
`tests/assert_safe_harbor_age_over_89_is_suppressed.sql` asserts the same
closure over the same five columns.

**The test reads the exact birth date, not the published year.** It joins
`stg_synthea__patients` and computes completed years. Year arithmetic on the
mart is ambiguous by a year in both directions, so a threshold loose enough to
avoid false positives is also loose enough to let a real 90-year-old through,
and the rule turns on the patient's actual age rather than on what subtraction
happens to yield. A test may read staging; the mart may not. The clause is not
vacuous: 5,799 fact rows across 35 patients do put a patient over 89 at a
published date, and every one of those patients has their year elements
withheld.

**What it changed in the output.** Nothing that is published. The reference
date moves for 257 patients, by up to 69 days, and that moves the computed
maximum age for 3 of them, each by one year. None of the three crosses the
threshold: the aggregated category still holds the same 35 patients, and no
year element that was published before is withheld now. The highest age any
combination of published columns yields is 89.

That result is the point rather than an argument against the change. The
narrow rule gave the right answer because no date happened to cross a birthday,
and the wide one gives it because the rule covers the dates. A rule that holds
by coincidence fails silently the first time the coincidence does, and section
19 exists because that had already happened here once.

**Against.** Leaving the rule on encounter starts and relying on the test to
catch a violation. Rejected: a test asserts the closure, it does not produce
it, and a build that fails on real data leaves nothing to ship.

**Consequence.** `dim_patient` now depends on `stg_synthea__conditions` as well
as on the encounter feed. A dimension reading a fact's source feed looks
backwards until you notice it was already doing it for the same reason. Any
third fact that publishes a date against `patient_id` has to be added to the
`published_dates` union here and to the union inside that test, and neither
will complain about the omission unless the new dates actually cross a
birthday, which is why this entry says so plainly.

**Amended 2026-09-23.** "The highest age any combination of published columns
yields is 89", under What it changed in the output, was not true when it was
written. It held for a published birth year set beside a published date, which
is what this section examined. It did not hold for the facts, which published
an exact age below 90 beside exact dates: an age at one date bounds a birth
year and a later date turns the bound back into an age, which recovered an age
over 89 for all 35 patients, up to 109. Nor did it hold for the dates alone,
which put 10 of the 35 over 89 by their span. Section 27 closes the first path
and records why the second cannot be closed, and the project no longer makes a
claim of that form. Section 27 also adds a third place a new fact's dates have
to go, the `published_dates` union in
`assert_fact_age_and_date_do_not_imply_over_89.sql`, and a fact that publishes
an age has to join `published_ages` there and `fact_rows` in
`assert_fact_age_is_withheld_for_the_protected_cohort.sql`.

**Amended again 2026-09-23.** "Asserts the same closure over the same five
columns", above, was not true when it was written, and the claim that the test
reads the exact birth date rather than the published year held for four of the
five. The test checked the death date by subtracting the published years,
`death_year - birth_year > 89`, which is the year arithmetic this section
rejects. That clause could not pass a violation, because a completed age over
89 always leaves the two years at least 90 apart. What it could do was fail a
compliant patient. Someone who died at 89, before the birthday that would have
made them 90, has a death year 90 after their birth year, and when no later
published date reaches that birthday the dimension's rule publishes both. No
such patient is in this sample, so the build never showed it. The death date
now sits in the test's exact-date union beside the four fact columns, and the
year clause is gone. 15 death dates put a patient over 89, and all 15 of those
patients have their year elements withheld.

## 23. A condition row is not a diagnosis

**Recorded 2026-09-04**, from profiling the feed before the fact was written.
Not a decision, but the fact a reader of `fct_condition` needs first.

29,749 of the 38,094 rows carry the SNOMED semantic tag `finding` rather than
`disorder`, nearly four to one. The most common code in the whole fact is
`160903007`, `Full-time employment (finding)`, on 13,805 rows, followed by
`Stress (finding)` on 5,137 and `Part-time employment (finding)` on 2,426.
Synthea writes employment status, social isolation and similar social context
onto the problem list the same way it writes pneumonia. So a count of rows in
this fact is a count of problem list entries, and reading it as a count of
diagnoses overstates them several times over. `fct_encounter.condition_count`
counts the same rows and inherits the same caveat.

**Why the tag is named for the source.** `dim_condition.source_semantic_tag` is
the parenthetical at the end of the description Synthea emitted, and that is
all it is. 95 of the 202 codes carry no tag, and the untagged group holds
plainly clinical labels including `Hypertension`, `Prediabetes` and
`Miscarriage in first trimester`, so the tag undercounts disorders and cannot
be used as a filter for them. Two further limits: the tag follows whichever
spelling the dimension chose, which is why code 84757009 reads `Epilepsy` with
no tag while 233604007 reads `Pneumonia (disorder)`; and code 80583007 arrives
as `Severe anxiety (panic) (finding` with the closing parenthesis missing, so
its tag is null as well.

**Why it is here rather than fixed.** This is section 16 again in a different
column. The generator's shape is not a defect the project can correct, and a
model that quietly filtered the social findings out would answer a question
nobody asked and disagree with staging for a reason no reader could see. Naming
it is the fix.

**What would reopen it.** A mart that genuinely needs a clinical category. The
path is a curated code list or a real SNOMED hierarchy loaded as a source, not
a string suffix.

## 24. Payer mix needs the program, not the sector

**Decided 2026-09-08.** `dim_payer` now carries two groupings of the same ten
payers. `payer_financial_class` names the program that pays: `medicare`,
`medicaid`, `dual_eligible`, `commercial`, `self_pay`. `payer_category` is the
older and coarser one and keeps its three values, `self_pay`, `public`,
`commercial`.

**Why the finer column.** `public` is the wrong width for the report this
dimension exists to serve. Medicare, Medicaid and dual eligible pay at
different rates and are separate lines on every payer mix a health system
reads, so collapsing them answers a question nobody asks. Across the 61,459
encounters the split is 33,231 commercial, 13,620 self pay, 8,482 Medicare,
5,283 Medicaid and 843 dual eligible. `public` reports those last three as one
number, 14,608, which hides that Medicare is 58 percent of public volume and
dual eligible is under 6 percent of it.

**Why both, rather than a rename.** `payer_category` is documented, tested and
already published, and the sector is the right width for some questions. The
finer column costs one column and one `accepted_values` test; replacing the
coarser one would break a reader for no gain.

**Why the rollup is derived from the class.** Two independent `case` lists over
the same ten names is the failure mode where a payer is added to one and
forgotten in the other, and no test would catch it: both columns still pass
`accepted_values`, and the wrong row is a value that exists. So
`payer_category` is computed from `payer_financial_class`, collapsing the three
public programs and passing the other two values through unchanged, and
`is_self_pay` is derived from the class for the same reason. There is one
mapping from payer name in this model, not three.

**What the column is not.** In a real revenue cycle, financial class is set on
the account, not on the payer, because one payer sells products in more than
one class: a Medicare Advantage plan under a commercial brand is financial
class Medicare, and the payer name would say the opposite. Nothing in this feed
supplies a plan or product. `payers.csv` carries a name, a headquarters
address, and lifetime money and count rollups; `encounters.csv` carries one
payer and a coverage amount. So the mapping from name to class is one to one
here and belongs on the dimension, which is true of this generator and not of a
real one.

Coverage is not one payer per patient either. `payer_transitions.csv` records a
secondary payer on 1,980 of its 53,101 coverage spans, and every one of them is
Medicare primary with a commercial supplement. That feed is not staged, and
`fct_encounter` carries a single `payer_id`, so the class on an encounter is
the class of its primary payer and nothing more. Note that Synthea models dual
coverage twice over: `Dual Eligible` is also a payer in its own right, on 255
spans, and those never carry a secondary.

**Against.** Deriving the class from anything but the name. There is nothing
else to derive it from, per the columns above. Also against: adding a
`medicare_advantage` value on the grounds that a real mix has one. Rejected as
section 16 and section 23 again, a category the data cannot support. Synthea
has one Medicare payer and no plan detail, so the value would be empty on every
row.

**What would reopen it.** A feed carrying the plan or the product, or a payer
selling in more than one class. Either one moves financial class off the
dimension and onto the encounter, because it would stop being an attribute of
the payer. Staging `payer_transitions` would also reopen it, since a secondary
payer makes the class of an encounter a function of two payers rather than one.

## 25. Length of stay counts midnights, and only for inpatients

**Decided 2026-09-08.** `fct_encounter.length_of_stay_days` is the discharge
date less the admission date, computed on the 1,728 encounters whose class is
`inpatient` and null on the other 59,731.
`tests/assert_length_of_stay_is_inpatient_only.sql` asserts that split, and
`tests/assert_inpatient_length_of_stay_is_plausible.sql` warns on stays longer
than a calendar year.

**Why only inpatients.** A length of stay is a census measure: it counts the
nights a bed was occupied. A fifteen-minute wellness visit does not have one.
Publishing zero on 59,731 rows would put a number in the column that means "not
applicable" while reading as "discharged the same day", and any average taken
over the fact without a class filter would then be wrong by a factor of thirty
five. Section 20 of this log is four columns renamed for exactly that failure,
a name promising something the values do not deliver. Null is the honest value,
and it costs one nullable measure in a fact where every other measure is
`not_null`.

**Why midnights rather than elapsed time.** `duration_minutes` already carries
elapsed time, so a length of stay divided out of it would be a unit and not a
measure. The number a hospital reports is a count of nights, because a bed is
billed and censused by the night and not by the hour. The two do not agree:
they differ on 158 of the 1,728 inpatient rows, so this is a second measure
rather than the first one rescaled.

**Why this does not contradict section 18.** That section rejected
`date_diff('year', ...)` as an age and this section adopts `date_diff('day',
...)` as a stay, which look like opposite rulings on the same function. They
are rulings on two different questions. Age is a duration a person has lived,
so counting calendar-year boundaries overstates it and completed years is the
answer. A stay is a count of nights a bed was held, so the boundaries crossed
are the answer and elapsed hours are not. The test in both cases is the same:
what does the number mean to the person reading it.

**The missing discharge rule.** There is none, deliberately. `stopped_at` is
`not_null` in staging and in the fact, and 61,459 of 61,459 rows carry one, so
no `coalesce` sits between the feed and the measure. If a future feed ever
carried an open stay, the `not_null` test fails first and loudly, rather than
the stay being silently measured against a null and landing as zero. A
`coalesce` to the current date would also break section 14, which is that
nothing in this project reads the clock.

**The same-day case.** Under this rule an admission and discharge on the same
date is 0 nights. No such encounter exists here; the minimum is 1 and 1,624 of
the 1,728 are exactly 1. Some health systems report a same-day stay as 1 day
instead. That convention is not applied here, because it would put a branch in
the model that no row in the build exercises, and an untested branch is a
liability rather than a safeguard.

**Consequence.** The build carries a second expected warning. One inpatient
stay runs 4,969 days, admitted 1996 and discharged 2010, which is a Synthea
artifact of the same kind as the post-death encounters in section 15 and is
handled the same way: warned, priced at 1 of 1,728, and not filtered. Three
more stays run between 57 and 335 days, which are long but not impossible, so
the threshold sits at a year rather than at the point the data thins out. The
test pins the tolerated count at 1 and errors above it, for the reason section
26 gives.

**What would reopen it.** A feed that distinguishes observation from inpatient,
or one that carries a discharge disposition. Either would make the scoping rule
a property of the encounter rather than an inference from its class.

## 26. A warning that does not fail on growth is not a control

**Decided 2026-09-10**, from a review of the length-of-stay change before it was
committed.

Two tests in this project are documented as reporting a known defect on every
run and turning into a failure the moment it grows. Section 15 has made that
claim since the first release. Both were configured `severity: warn` and nothing
else, and that configuration does not do it. `severity: warn` warns whenever the
test returns any rows, at any count. The post-death test would have reported the
same single warning at 165 rows and at 1,650, and CI, which treats a warning as
success, would have stayed green through a tenfold regression.

The threshold form does what the prose promised:

```
{{ config(severity = 'error', warn_if = '> 0', error_if = '> 165') }}
```

`severity: warn` is not that form with a default. Setting `severity: warn`
alongside an `error_if` discards the threshold; dbt 1.12.3 reports `configured
to warn if != 0` and warns, whatever the count. Only `severity: error` evaluates
both bounds, warning above `warn_if` and failing above `error_if`.

**Consequence.** The tolerated count is now pinned in each test at the count
that exists today: 165 for the post-death encounters, 1 for the implausible
inpatient stay. The build still ends `WARN=2 ERROR=0`, because both counts sit
at their bound. One more post-death encounter, or one more year-long stay, is an
error and fails CI. The pinned numbers are the cost: a change that legitimately
moves either count has to move the bound in the same commit, which is the point,
because that is the moment a human should be looking.

**Why not soften the prose instead.** That was the cheaper fix and it was
rejected. The two tests are the project's argument that a known defect can be
priced rather than hidden, and an unenforced control is worse than an honest
absence of one: it reads as a guarantee to anyone who does not open the file.
The repository is public, and the claim was checkable and wrong.

**What would reopen it.** A count that moves for a legitimate reason often
enough that the bound becomes churn. That would mean the defect is not stable,
which is itself the signal the test exists to give.

## 27. A capped age is not a suppressed age

**Decided 2026-09-18**, from a peer review of the Governance claims, confirmed
against the built warehouse before anything was changed.

Both facts published `patient_age_years` as the exact completed age whenever it
was below 90, capped only at 90 or above. Section 12 treated that cap as the
fact's half of the over-89 rule. It is not, and the gap is not subtle: an exact
age beside an exact service date bounds a birth year, and any later published
date for the same patient turns that bound back into an age.

For patient `864b2fa0` an encounter at age 87 on 2013-12-25 puts the birth no
later than 1926-12-25, and a published date of 2021-11-17 for the same patient
yields a guaranteed 94. Across the cohort every one of the 35 protected patients
was recoverable this way, to a maximum of 109. No dimension column is involved,
so every defence sections 12, 19 and 22 describe was bypassed rather than
broken. `tests/assert_safe_harbor_age_over_89_is_suppressed.sql` could not see
it: its cross-fact clause is gated on `birth_year is not null`, which selects
exactly the patients who are not protected.

**The fix is to withhold, not to cap harder.** Both facts now publish no age at
all for the 35, taking the cohort from `dim_patient.is_age_90_or_older` rather
than recomputing it, so the cohort the facts suppress and the cohort the
dimension aggregates are one definition. `dim_patient` reads only staging, so a
fact referencing it is not a cycle.

Stamping 90 on those rows instead would have been worse than the cap it
replaced. A 90 against a date when the patient was 87 is a stronger anchor than
the true age was, because it moves the implied birth three years earlier. The
maximum derivable age under that variant is 199, against 109 for the defect it
was meant to fix. This was caught in review before it was written, and it is the
reason this entry says withhold rather than cap.

**What it does not fix, which is now stated rather than implied.** Ten of the 35
have published events more than 89 years apart, the widest span 109 years, so
the later event guarantees an age over 89 from the dates alone with no age
column involved. The facts keep exact dates on purpose, section 19, so this is
not closable without giving that up. No claim of the form "no combination of
published columns recovers an age" is therefore available to this project, and
the README and the portfolio site no longer make one. Safe Harbor is claimed for
`dim_patient` and not for the marts, which is what section 19 already said and
what now has to carry the weight alone.

**Consequence.** `fct_encounter` publishes an age on 55,685 of 61,459 rows and
`fct_condition` on 34,338 of 38,094; the highest published age in either is 88.
Neither column is `not_null` any more, which is deliberate and is why both
descriptions say so. Two tests replace the two dropped `not_null` tests:
`assert_fact_age_and_date_do_not_imply_over_89.sql` does the attacker's
arithmetic and asserts the result stays at or below 89, and
`assert_fact_age_is_withheld_for_the_protected_cohort.sql` asserts the scoping
rule for the reason section 25 gives, and additionally catches over-suppression,
which the arithmetic test cannot see. Test counts are unchanged at 206, now 188
generic and 18 singular.

**Amended 2026-09-23.** Two statements above were wrong. The widest span is 108
years, not 109: its dates are 1912-09-26 and 2021-06-25, 108 completed years
apart, and 109 was the count of calendar-year boundaries between them, which
section 18 rejects as an age. The later date still guarantees an age over 89, so
the conclusion stands. And the README did still make a claim of the "no
combination" form, in one sentence of its Data quality section that this change
did not reach, beside two fact model comments that still called the age capped
at 90. All three were corrected on this date, and section 22 carries its own
amendment for the same claim.

**Amended again 2026-09-23.** "Safe Harbor is claimed for `dim_patient` and not
for the marts", above, now claims less. The dimension's key is the source
system's own patient identifier, so it is not a Safe Harbor data set either,
and the project claims the rules it applies rather than the data set. Section
28.

**Extended 2026-09-23.** One capped age remains in the marts,
`dim_patient.age_at_death_years`, which publishes 90 for the 15 patients who
died at 90 or older. A cap is enough there for the reason it was not on the
facts. An age bounds a birth year only against the date it was measured at, and
for this column that date is the death, whose year the dimension withholds for
everyone in the 90-or-older category. What the column lacked was a test:
removing the cap would have published ages up to 103 with every test passing.
`tests/assert_safe_harbor_age_over_89_is_suppressed.sql` now fails on any value
over 90.

**What would reopen it.** Dropping exact dates from the facts, which would make
the stronger claim available and is a different project. Or a mart that needs an
age for a protected patient, which would have to take it as the aggregated
category rather than as a number.

## 28. A source system key is not a re-identification code

**Decided 2026-09-23**, found while rewording how the project describes its
Safe Harbor work, and confirmed in review before anything was changed.

`dim_patient` has been keyed on `patient_id` since the first release. It is the
Synthea patient `Id`: the key of the patient feed, the foreign key in every
feed that records something about a patient, the key of `stg_synthea__patients`
beside names and exact birth dates, and the foreign key both facts carry.
Section 12 claimed the dimension as a Safe Harbor data set, and no entry in this
log examined its key under that rule. Section 13 chose the key for joins, and
the column description called it synthetic and internal to the dataset rather
than asking what the rule makes of it.

The rule makes it an identifier. 45 CFR 164.514(b)(2)(i)(R) removes any other
unique identifying number, characteristic or code. The exception in
164.514(c) is a re-identification code, and it holds only when the code is not
derived from or related to information about the individual, cannot otherwise
be translated to identify them, is not used or disclosed for any other purpose,
and the mechanism for re-identification is not disclosed. A random UUID is
derived from nothing about the patient. It still fails the third condition,
because a source system's patient key is used for everything that system does.
So `dim_patient` is not a Safe Harbor data set while it carries that key, and
it was not one when section 12 said it was.

**What is claimed now.** `dim_patient` applies Safe Harbor's rules for names,
geography, dates and ages over 89, and three tests enforce them, one on the
column list and two on the data. That is what this project can show, and it is
what the README, the model description, CONTRIBUTING and the test comments now
say. Section 19 withheld the claim from the marts because the facts keep exact
dates, and this section withholds it from the dimension because of its key.
The data is synthetic and holds no PHI, so nothing here is de-identified under
HIPAA in the literal sense. The transformations and the tests that hold them
are the deliverable, which is what section 12 said from the start.

**Against: replacing the key.** A study key in the marts, with the crosswalk
kept out of anything published, is how a real release is built, and it was
rejected here on cost rather than on possibility. A hash of the UUID can be
recomputed by anyone who holds staging, so it can be translated, and a
crosswalk checked in as a seed publishes the mechanism 164.514(c) says must not
be disclosed. What would qualify is a code drawn at random, either at build
time into a model nothing publishes, which gives every patient a different key
on every build, or once and stored outside the repository, which leaves a
fresh clone unable to build the marts. Either way every patient join in the
star is re-keyed, against section 13, to keep a sentence true rather than to
answer anything the marts are for.

**Against: a separate release model.** A model without `patient_id`, joined to
nothing, would carry the full claim. It would also be the only model in the
project that no question reads, built to hold a claim rather than to answer
one.

**Consequence.** No column changes and no number about the data moves. The
claim narrows on every surface that stated it, sections 12, 19 and 27 carry
dated amendments that point here, section 13 carries an extension, and the
description of `patient_id` says what the key is.

Review of the narrowed claim found two places where it still said more than the
tests show, and both are fixed rather than reworded. The column test was named
for direct identifiers while the dimension keeps one, so it is renamed for what
it checks, `assert_patient_dimension_excludes_name_place_and_date_columns.sql`.
And the geography rule was claimed as tested when nothing read `zip3`: the
column test would pass a full ZIP published under that name.
`tests/assert_patient_zip3_is_a_permitted_prefix.sql` now asserts that every
published value is three digits and none is a prefix HHS restricts. It reads
the list from `macros/restricted_zip3_prefixes.sql`, as the model does, so the
two cannot disagree about it. Published as a full ZIP, the column would fail it
on all 618 patients who have one. 207 tests, 19 of them singular.

**What would reopen it.** A requirement to publish a Safe Harbor release of this
data. The path then is a release model or pipeline that assigns its own code
and keeps the crosswalk out of the published repository, not a re-keyed star.
