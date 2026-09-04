-- Singular test: the conditions feed has no key column, so the fact carries no
-- single-column key either and the `unique` generic test cannot run on it. The
-- grain is asserted here instead, on the mart, the same way
-- assert_condition_grain_is_unique.sql asserts it on the staging model. Both
-- are needed: staging being unique does not prove the fact preserved it.
-- Returns the offending groups; the test passes when it returns none.
select patient_id, encounter_id, condition_code, count(*) as rows_in_group
from {{ ref('fct_condition') }}
group by patient_id, encounter_id, condition_code
having count(*) > 1
