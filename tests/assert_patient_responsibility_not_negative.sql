-- Singular test: a patient cannot owe less than nothing. A negative balance
-- would mean the payer covered more than the encounter was billed for.
-- Returns the offending rows; the test passes when it returns none.
select encounter_id, total_claim_cost, payer_coverage, patient_responsibility
from {{ ref('fct_encounter') }}
where patient_responsibility < 0
