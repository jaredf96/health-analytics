-- Reproduces the payer_transitions figures in docs/DECISIONS.md section 24 from
-- a feed no model reads. It is an analysis rather than a test: it reports what
-- the feed holds and asserts nothing, so the figures here are what section 24
-- is checked against. docs/DECISIONS.md section 29.
--
-- Run it with: dbt show --select profile_payer_transitions --limit 50 --output json
-- One row per figure. n is the count and of_n the spans it is a count of. The
-- financial class of each payer is the one dim_payer assigns, so the profile
-- and the marts classify a payer the same way.
with spans as (

    select
        t.PAYER,
        t.SECONDARY_PAYER,
        primary_payer.payer_financial_class             as primary_class,
        secondary_payer.payer_financial_class           as secondary_class
    from {{ source('synthea', 'payer_transitions') }} t
    left join {{ ref('dim_payer') }} primary_payer
        on t.PAYER = primary_payer.payer_id
    left join {{ ref('dim_payer') }} secondary_payer
        on t.SECONDARY_PAYER = secondary_payer.payer_id

),

figures (sort, figure, n, of_n) as (

    select 1, 'coverage spans', count(*), null from spans
    union all select 2, 'spans whose primary payer does not resolve', count(*) filter (where primary_class is null), count(*) from spans
    union all select 3, 'spans whose secondary payer does not resolve', count(*) filter (where SECONDARY_PAYER is not null and secondary_class is null), count(*) from spans
    union all select 4, 'spans with a secondary payer', count(SECONDARY_PAYER), count(*) from spans
    union all
    select 5, 'spans with a secondary payer, ' || primary_class || ' primary and ' || secondary_class || ' secondary',
           count(*), (select count(SECONDARY_PAYER) from spans)
    from spans
    where SECONDARY_PAYER is not null
    group by primary_class, secondary_class
    union all select 6, 'spans whose primary payer is dual eligible', count(*) filter (where primary_class = 'dual_eligible'), count(*) from spans
    union all select 7, 'dual eligible spans with a secondary payer', count(SECONDARY_PAYER) filter (where primary_class = 'dual_eligible'), count(*) filter (where primary_class = 'dual_eligible') from spans

)

select figure, n, of_n
from figures
order by sort, figure
