-- Singular test: the Safe Harbor rule for ages over 89, checked against the
-- data rather than against the column names.
--
-- 45 CFR 164.514(b)(2)(i)(C) allows ages over 89 to be aggregated into a
-- single category, and requires the elements of dates indicative of such an
-- age, the year included, to go with them. A capped age column alone does not
-- satisfy that: publishing a birth year beside it lets one subtraction
-- recover the age the cap was hiding, and joining that birth year to a date
-- on a fact does the same for every row of that patient.
--
-- The rule has to hold across every date the marts publish, on both facts and
-- on both ends of each period. This asserts it with the exact birth date from
-- staging rather than with year arithmetic on the mart. Year arithmetic is
-- ambiguous by a year in both directions, so a threshold loose enough to
-- avoid false positives is also loose enough to miss a real 90-year-old, and
-- what the rule turns on is the patient's actual age, not what subtraction
-- happens to yield. A test may read staging; the mart may not.
--
-- Returns the offending rows; the test passes when it returns none.

-- A patient in the aggregated category still carrying a year element.
select
    patient_id,
    'year element retained for an over-89 patient'      as violation
from {{ ref('dim_patient') }}
where is_age_90_or_older
  and (birth_year is not null or death_year is not null)

union all

-- Two year elements that subtract to an age the cap is supposed to hide.
select
    patient_id,
    'birth and death years imply an age over 89'        as violation
from {{ ref('dim_patient') }}
where death_year - birth_year > 89

union all

-- A published birth year beside any date either fact publishes for that
-- patient, where the two together land on a completed age over 89. Every date
-- column of both facts is checked, because the latest one is not always the
-- one you would guess: dates after death exist here, encounters can end long
-- after they start, and a condition outlives the visit that recorded it.
select
    d.patient_id,
    'a published fact date puts this patient over 89'   as violation
from {{ ref('dim_patient') }} d
inner join {{ ref('stg_synthea__patients') }} s
    on d.patient_id = s.patient_id
inner join (

    select patient_id, cast(started_at as date) as published_date
    from {{ ref('fct_encounter') }}

    union all

    select patient_id, cast(stopped_at as date) as published_date
    from {{ ref('fct_encounter') }}

    union all

    select patient_id, started_date             as published_date
    from {{ ref('fct_condition') }}

    union all

    select patient_id, stopped_date             as published_date
    from {{ ref('fct_condition') }}
    where stopped_date is not null

) f
    on d.patient_id = f.patient_id
where d.birth_year is not null
  and {{ completed_years('s.birth_date', 'f.published_date') }} > 89

union all

-- The cap itself, on both facts.
select
    patient_id,
    'patient_age_years exceeds the cap'                 as violation
from {{ ref('fct_encounter') }}
where patient_age_years > 90

union all

select
    patient_id,
    'condition patient_age_years exceeds the cap'       as violation
from {{ ref('fct_condition') }}
where patient_age_years > 90
