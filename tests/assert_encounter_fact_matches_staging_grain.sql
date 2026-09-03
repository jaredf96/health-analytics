-- Singular test: the fact must not filter. It carries one row per staged
-- encounter and no others, so the two sets differ nowhere.
-- Returns the offending ids; the test passes when it returns none.
select encounter_id, 'missing from fact' as problem
from {{ ref('stg_synthea__encounters') }}
where encounter_id not in (select encounter_id from {{ ref('fct_encounter') }})

union all

select encounter_id, 'not in staging' as problem
from {{ ref('fct_encounter') }}
where encounter_id not in (select encounter_id from {{ ref('stg_synthea__encounters') }})
