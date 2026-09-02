-- Singular test: a death date earlier than the birth date is impossible.
-- Returns the offending rows; the test passes when it returns none.
select patient_id, birth_date, death_date
from {{ ref('stg_synthea__patients') }}
where death_date is not null
  and death_date < birth_date
