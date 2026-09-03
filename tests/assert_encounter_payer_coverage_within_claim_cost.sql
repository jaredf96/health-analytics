-- Singular test: a payer cannot cover more than the encounter was billed for.
-- Returns the offending rows; the test passes when it returns none.
select encounter_id, total_claim_cost, payer_coverage
from {{ ref('stg_synthea__encounters') }}
where payer_coverage > total_claim_cost
