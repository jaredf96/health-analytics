-- Singular test: an encounter cannot end before it starts.
-- Returns the offending rows; the test passes when it returns none.
select encounter_id, started_at, stopped_at
from {{ ref('stg_synthea__encounters') }}
where stopped_at < started_at
