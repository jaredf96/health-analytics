-- Singular test: an encounter reason arrives as a code and a label together,
-- or not at all. One without the other means a broken feed.
-- Returns the offending rows; the test passes when it returns none.
select encounter_id, reason_code, reason_description
from {{ ref('stg_synthea__encounters') }}
where (reason_code is null) != (reason_description is null)
