-- Singular test: the fact must not filter. It carries one row per staged
-- encounter and no others, so the two sets differ nowhere.
--
-- Both halves are left joins rather than `not in`. A single null encounter_id
-- in the subquery of a `not in` makes the predicate null for every row, so the
-- test would pass however many encounters were missing. A left join reports
-- the null row instead of losing the assertion. The not_null tests on
-- encounter_id catch a null in a full build, but this test is run alone often
-- enough that it should not depend on them.
-- Returns the offending ids; the test passes when it returns none.
select
    s.encounter_id,
    'missing from fact' as problem
from {{ ref('stg_synthea__encounters') }} s
left join {{ ref('fct_encounter') }} f
    on s.encounter_id = f.encounter_id
where f.encounter_id is null

union all

select
    f.encounter_id,
    'not in staging' as problem
from {{ ref('fct_encounter') }} f
left join {{ ref('stg_synthea__encounters') }} s
    on f.encounter_id = s.encounter_id
where s.encounter_id is null
