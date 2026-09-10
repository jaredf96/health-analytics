-- Singular test: length_of_stay_days is populated on exactly the inpatient
-- encounters and null on every other class. The scoping rule lives in a case
-- expression in fct_encounter, and without this test it would be a convention
-- rather than an assertion: a later edit could widen the measure to classes
-- where a length of stay has no meaning, or narrow it, and nothing would say
-- so. 1,728 rows carry a value and 59,731 do not.
--
-- The comparison is `is distinct from` rather than `<>` so that the assertion
-- is total. A null encounter_class would make `encounter_class = 'inpatient'`
-- null, and `<>` between a null and a boolean is null, so the offending row
-- would escape the where clause and the test would pass on it. The not_null
-- test on encounter_class catches that in a full build, but this test is run
-- alone often enough that it should not depend on another one.
-- Returns the offending rows; the test passes when it returns none.
select
    encounter_id,
    encounter_class,
    length_of_stay_days
from {{ ref('fct_encounter') }}
where (encounter_class = 'inpatient') is distinct from (length_of_stay_days is not null)
