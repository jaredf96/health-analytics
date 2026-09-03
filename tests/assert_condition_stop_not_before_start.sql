-- Singular test: a condition cannot end before it starts.
-- Returns the offending rows; the test passes when it returns none.
select patient_id, encounter_id, condition_code, started_date, stopped_date
from {{ ref('stg_synthea__conditions') }}
where stopped_date is not null
  and stopped_date < started_date
