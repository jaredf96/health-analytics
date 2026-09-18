-- Singular test: patient_age_years is null on exactly the fact rows belonging
-- to the patients the over-89 rule protects, and present on every other row.
--
-- The companion test, assert_fact_age_and_date_do_not_imply_over_89.sql, is the
-- one that matters, because it checks the arithmetic an attacker would do. This
-- one checks the rule the models implement, for the reason section 25 gives
-- about length of stay: a scoping rule that lives only in a case expression is
-- a convention rather than an assertion, and a later edit could narrow or widen
-- it with nothing to say so. It also catches over-suppression, which the
-- arithmetic test cannot see: withholding every age in both facts would pass
-- that test and destroy the column.
-- Returns the offending rows; the test passes when it returns none.

with protected as (

    select patient_id from {{ ref('dim_patient') }} where is_age_90_or_older

),

fact_rows as (

    select 'fct_encounter' as fact, encounter_id as row_key, patient_id, patient_age_years
    from {{ ref('fct_encounter') }}
    union all
    select 'fct_condition', patient_id || '|' || condition_code, patient_id, patient_age_years
    from {{ ref('fct_condition') }}

)

select f.fact, f.row_key, f.patient_id, f.patient_age_years
from fact_rows f
left join protected p
    on f.patient_id = p.patient_id
where (p.patient_id is not null) is distinct from (f.patient_age_years is null)
