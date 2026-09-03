-- Singular test: the conditions feed has no key column, so the grain is
-- asserted here instead. A patient cannot have the same condition code
-- recorded twice at one encounter.
-- Returns the offending groups; the test passes when it returns none.
select patient_id, encounter_id, condition_code, count(*) as rows_in_group
from {{ ref('stg_synthea__conditions') }}
group by patient_id, encounter_id, condition_code
having count(*) > 1
