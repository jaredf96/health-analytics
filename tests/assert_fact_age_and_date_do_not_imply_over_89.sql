-- Singular test: no age either fact publishes, set beside a date either fact
-- publishes for the same patient, implies a completed age over 89.
--
-- This is the path assert_safe_harbor_age_over_89_is_suppressed.sql does not
-- cover. That test asks whether a birth year the DIMENSION publishes lands on a
-- hidden age, and its cross-fact clause is gated on `birth_year is not null`,
-- which is exactly what the protected patients do not have. The leak needs no
-- dimension column at all: an exact age A at a published date D1 puts the birth
-- no later than D1 minus A years, and any later published date for the same
-- patient converts that bound into an age. Before the cohort's ages were
-- withheld this recovered an age over 89 for all 35 of them, up to 109.
--
-- The bound is what an attacker can GUARANTEE, not what is likely: the latest
-- birth consistent with a completed age of A at D1 is D1 minus A years, so the
-- age it implies at a later date is a floor rather than an estimate. The
-- patient's own latest published date is used because the implied age only
-- grows with the date, so that one date maximises it.
--
-- This is deliberately not a test of the cohort flag. Reading the flag would
-- only confirm the model does what the model says; reading the arithmetic
-- catches a cohort that is wrong as well as a suppression that is missing.
--
-- Returns the offending rows; the test passes when it returns none.

with published_dates as (

    select patient_id, cast(started_at as date) as published_date from {{ ref('fct_encounter') }}
    union all
    select patient_id, cast(stopped_at as date)                   from {{ ref('fct_encounter') }}
    union all
    select patient_id, started_date                               from {{ ref('fct_condition') }}
    union all
    select patient_id, stopped_date                               from {{ ref('fct_condition') }}
    where stopped_date is not null

),

latest_published as (

    select patient_id, max(published_date) as latest_date
    from published_dates
    group by patient_id

),

published_ages as (

    select patient_id, cast(started_at as date) as anchor_date, patient_age_years as anchor_age
    from {{ ref('fct_encounter') }}
    where patient_age_years is not null
    union all
    select patient_id, started_date, patient_age_years
    from {{ ref('fct_condition') }}
    where patient_age_years is not null

)

select
    a.patient_id,
    a.anchor_age,
    a.anchor_date,
    l.latest_date,
    {{ completed_years('(a.anchor_date - to_years(cast(a.anchor_age as int)))', 'l.latest_date') }} as implied_age
from published_ages a
inner join latest_published l
    on a.patient_id = l.patient_id
where {{ completed_years('(a.anchor_date - to_years(cast(a.anchor_age as int)))', 'l.latest_date') }} > 89
