-- Condition dimension, one row per SNOMED CT condition code.
-- The feed has the same problem here that it has with encounter types: a code
-- does not determine its description. Two codes carry two spellings each, so
-- the rule is the one dim_encounter_type uses. It picks the spelling recorded
-- on the most rows and breaks ties on the description text, so the result does
-- not depend on row order.
--
-- source_semantic_tag is the parenthetical SNOMED CT tags the description
-- carries, and it is named for the source because the source is all it
-- reflects: 95 of the 202 codes have no tag at all, and one arrives with an
-- unclosed parenthesis. It is not a clinical classification, and nothing in
-- this project treats it as one. What it does show is that 29,749 of the
-- 38,094 rows in fct_condition are findings rather than disorders, which is
-- the first thing a reader of that fact needs to know.

with conditions as (

    select * from {{ ref('stg_synthea__conditions') }}

),

spellings as (

    select
        condition_code,
        condition_description,
        count(*) as condition_count
    from conditions
    group by condition_code, condition_description

),

ranked as (

    select
        condition_code,
        condition_description,
        row_number() over (
            partition by condition_code
            order by condition_count desc, condition_description
        ) as spelling_rank,
        count(*) over (partition by condition_code) as spelling_count,
        sum(condition_count) over (partition by condition_code) as total_condition_count
    from spellings

),

patients_per_code as (

    select
        condition_code,
        count(distinct patient_id) as patient_count
    from conditions
    group by condition_code

)

select
    r.condition_code,
    r.condition_description,
    -- Empty when the description ends in no parenthetical, which regexp_extract
    -- returns as an empty string rather than as null.
    nullif(regexp_extract(r.condition_description, '\(([^()]+)\)$', 1), '')
                                as source_semantic_tag,
    r.spelling_count            as source_spelling_count,
    r.total_condition_count     as condition_count,
    p.patient_count
from ranked r
inner join patients_per_code p
    on r.condition_code = p.condition_code
where r.spelling_rank = 1
