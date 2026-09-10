-- Singular test, WARN severity: an inpatient stay should not run longer than a
-- calendar year. One of the 1,728 inpatient encounters does, at 4,969 days,
-- admitted 1996 and discharged 2010. Nothing filters it. Two more sit between
-- half a year and a year, at 335 and 236 days, and one runs 57 days; those are
-- long but not impossible for a complex course, so the line is drawn where no
-- reading of an acute inpatient stay survives rather than where the data
-- happens to thin out.
--
-- Warned for the same reason as the post-death test, section 15 of
-- docs/DECISIONS.md: the count is reported on every run rather than hidden. The
-- tolerated count is pinned at the 1 stay that exists today, so the test warns
-- at 1 and errors at 2. A bare severity of warn would not do that; it warns at
-- any count, which made the same claim on the post-death test untrue until
-- section 26. The floor needs no assertion here;
-- tests/assert_encounter_stop_not_before_start.sql already rules out a
-- discharge before an admission, so the measure cannot go negative.
-- Returns the offending rows; the test warns at 1 and fails above it.
{{ config(severity = 'error', warn_if = '> 0', error_if = '> 1') }}

select
    encounter_id,
    patient_id,
    started_at,
    stopped_at,
    length_of_stay_days
from {{ ref('fct_encounter') }}
where length_of_stay_days > 365
