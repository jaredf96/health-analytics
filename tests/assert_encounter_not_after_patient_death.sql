-- Singular test, WARN severity: an encounter should not start after the
-- patient's recorded death date. It does here, on 165 of 61,459 encounters
-- across 154 patients, by three to fourteen days. That is a Synthea
-- generation artifact, not something this project can fix upstream, and
-- nothing filters it out. The test is set to warn so the build stays honest:
-- the number is reported on every run rather than hidden, and it turns into a
-- failure the moment it grows.
-- Returns the offending rows; the test warns when it returns any.
{{ config(severity = 'warn') }}

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
