-- Payer dimension. The one rule applied here is payer_category, which splits
-- the ten payers into the three groups a payer-mix report actually needs.
-- NO_INSURANCE is Synthea's self-pay stand-in and is the payer on more
-- encounters than any real plan, so it is categorized explicitly rather than
-- left to be mistaken for a commercial plan.

with payers as (

    select * from {{ ref('stg_synthea__payers') }}

),

categorized as (

    select
        payer_id,
        payer_name,
        case
            when payer_name = 'NO_INSURANCE' then 'self_pay'
            when payer_name in ('Medicare', 'Medicaid', 'Dual Eligible') then 'public'
            else 'commercial'
        end                             as payer_category,
        payer_name = 'NO_INSURANCE'     as is_self_pay,

        headquarters_state,
        amount_covered                  as lifetime_amount_covered,
        amount_uncovered                as lifetime_amount_uncovered,
        revenue                         as lifetime_revenue,
        covered_encounters              as lifetime_covered_encounters,
        uncovered_encounters            as lifetime_uncovered_encounters,
        unique_customers                as lifetime_unique_customers,
        member_months                   as lifetime_member_months,
        quality_of_life_score_avg       as quality_of_life_score_avg

    from payers

)

select * from categorized
