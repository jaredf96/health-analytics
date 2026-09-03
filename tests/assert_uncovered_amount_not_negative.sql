-- Singular test: a payer cannot cover more than the encounter was billed, so
-- the uncovered residual cannot be negative.
-- Returns the offending rows; the test passes when it returns none.
select encounter_id, total_claim_cost, payer_coverage, uncovered_amount
from {{ ref('fct_encounter') }}
where uncovered_amount < 0
