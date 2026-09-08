-- Payer dimension. Two groupings of the ten payers, at two widths.
-- payer_financial_class is the finer one and names the program that pays.
-- Medicare, Medicaid and Dual Eligible stay apart there because they pay at
-- different rates, which is the distinction a payer-mix report turns on.
-- payer_category rolls those three into public, which is the width a coverage
-- or volume split is usually read at. The rollup is derived from the class
-- rather than mapped from the payer name a second time, so the two columns
-- cannot disagree. NO_INSURANCE is Synthea's self-pay stand-in and is the
-- payer on more encounters than any real plan, so it is classed explicitly
-- rather than left to be mistaken for a commercial plan.

with payers as (

    select * from {{ ref('stg_synthea__payers') }}

),

classified as (

    select
        *,
        case
            when payer_name = 'NO_INSURANCE'  then 'self_pay'
            when payer_name = 'Medicare'      then 'medicare'
            when payer_name = 'Medicaid'      then 'medicaid'
            when payer_name = 'Dual Eligible' then 'dual_eligible'
            else 'commercial'
        end as payer_financial_class

    from payers

),

categorized as (

    select
        payer_id,
        payer_name,
        payer_financial_class,

        -- the rollup: the three public programs collapse, the rest pass through
        case
            when payer_financial_class in ('medicare', 'medicaid', 'dual_eligible')
                then 'public'
            else payer_financial_class
        end                                     as payer_category,
        payer_financial_class = 'self_pay'      as is_self_pay,

        headquarters_state,
        amount_covered                          as lifetime_amount_covered,
        amount_uncovered                        as lifetime_amount_uncovered,
        revenue                                 as lifetime_revenue,
        covered_encounters                      as lifetime_covered_encounters,
        uncovered_encounters                    as lifetime_uncovered_encounters,
        unique_customers                        as lifetime_unique_customers,
        member_months                           as lifetime_member_months,
        quality_of_life_score_avg               as quality_of_life_score_avg

    from classified

)

select * from categorized
