-- Singular test, WARN severity: an encounter should not start after the
-- patient's recorded death date. It does here, on 165 of 61,459 encounters
-- across 154 patients, by one to fourteen days. That is a Synthea
-- generation artifact, not something this project can fix upstream, and
-- nothing filters it out. The test warns so the build stays honest: the number
-- is reported on every run rather than hidden. The tolerated count is pinned at
-- the 165 that exist today, so the test warns at 165 and errors at 166, which
-- is what makes growth a failure rather than a louder warning. A bare severity
-- of warn warns at any count and would not; docs/DECISIONS.md section 26.
-- Returns the offending rows; the test warns at 165 and fails above it.
{{ config(severity = 'error', warn_if = '> 0', error_if = '> 165') }}

select
    e.encounter_id,
    e.patient_id,
    cast(e.started_at as date) as encounter_date,
    p.death_date,
    date_diff('day', p.death_date, cast(e.started_at as date)) as days_after_death
from {{ ref('fct_encounter') }} e
inner join {{ ref('stg_synthea__patients') }} p
    on e.patient_id = p.patient_id
where p.death_date is not null
  and cast(e.started_at as date) > p.death_date
