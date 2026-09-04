-- Singular test: the fact must not filter. It carries one row per staged
-- condition and no others, so the two sets differ nowhere. The comparison is
-- on the three columns that identify a row, because the feed supplies no key.
-- Returns the offending keys; the test passes when it returns none.
select
    s.patient_id,
    s.encounter_id,
    s.condition_code,
    'missing from fact' as problem
from {{ ref('stg_synthea__conditions') }} s
left join {{ ref('fct_condition') }} f
    on  s.patient_id = f.patient_id
    and s.encounter_id = f.encounter_id
    and s.condition_code = f.condition_code
where f.patient_id is null

union all

select
    f.patient_id,
    f.encounter_id,
    f.condition_code,
    'not in staging' as problem
from {{ ref('fct_condition') }} f
left join {{ ref('stg_synthea__conditions') }} s
    on  f.patient_id = s.patient_id
    and f.encounter_id = s.encounter_id
    and f.condition_code = s.condition_code
where s.patient_id is null
