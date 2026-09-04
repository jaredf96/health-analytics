-- Singular test: the two facts have to agree about who was seen. A condition
-- row names both a patient and an encounter, and the encounter names a patient
-- of its own, so a disagreement would file the same event under two people and
-- would break any measure that groups one fact by a dimension reached through
-- the other. This is what conforming dimensions across two facts has to mean
-- in practice, and it is the assertion a relationships test cannot make: both
-- foreign keys can resolve while pointing at different patients.
-- Returns the offending rows; the test passes when it returns none.
select
    c.encounter_id,
    c.condition_code,
    c.patient_id as condition_patient_id,
    e.patient_id as encounter_patient_id
from {{ ref('fct_condition') }} c
inner join {{ ref('fct_encounter') }} e
    on c.encounter_id = e.encounter_id
where c.patient_id <> e.patient_id
