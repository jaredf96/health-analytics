-- Encounter type dimension, one row per SNOMED CT encounter code.
-- A code does not determine its description in this feed: six codes carry more
-- than one spelling, including case variants of the same words. The rule here
-- picks the spelling used on the most encounters, breaking ties on the
-- description text so the result does not depend on row order.
-- A code does not determine encounter_class either; five codes appear in more
-- than one class, so class stays on the fact as a degenerate dimension rather
-- than being attached here where it would be wrong.

with encounters as (

    select * from {{ ref('stg_synthea__encounters') }}

),

spellings as (

    select
        encounter_code,
        encounter_description,
        count(*) as encounter_count
    from encounters
    group by encounter_code, encounter_description

),

ranked as (

    select
        encounter_code,
        encounter_description,
        encounter_count,
        row_number() over (
            partition by encounter_code
            order by encounter_count desc, encounter_description
        ) as spelling_rank,
        count(*) over (partition by encounter_code) as spelling_count,
        sum(encounter_count) over (partition by encounter_code) as total_encounter_count
    from spellings

)

select
    encounter_code,
    encounter_description,
    spelling_count          as source_spelling_count,
    total_encounter_count   as encounter_count
from ranked
where spelling_rank = 1
