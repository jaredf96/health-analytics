-- Singular test: the Safe Harbor rule for ages over 89, checked against the
-- data rather than against the column names.
--
-- 45 CFR 164.514(b)(2)(i)(C) allows ages over 89 to be aggregated into a
-- single category, and requires the elements of dates indicative of such an
-- age, the year included, to go with them. A capped age column alone does not
-- satisfy that: publishing a birth year beside it lets one subtraction
-- recover the age the cap was hiding, and joining that birth year to a date
-- on the fact does the same for every encounter of that patient.
--
-- This asserts all three closures at once. Returns the offending rows; the
-- test passes when it returns none.

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

-- A capped age on the fact undone by joining the dimension back to it.
select
    f.patient_id,
    'fact date and birth_year recover an age over 89'   as violation
from {{ ref('fct_encounter') }} f
join {{ ref('dim_patient') }} d using (patient_id)
where d.birth_year is not null
  and year(f.started_at) - d.birth_year > 90

union all

-- The cap itself.
select
    patient_id,
    'patient_age_years exceeds the cap'                 as violation
from {{ ref('fct_encounter') }}
where patient_age_years > 90
