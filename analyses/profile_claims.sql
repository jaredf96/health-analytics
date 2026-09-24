-- Reproduces the claims profile in docs/DECISIONS.md section 8 from the two
-- claims feeds, which no model reads. It is an analysis rather than a test: it
-- reports what the feed holds and asserts nothing, so the figures here are
-- what section 8 is checked against. docs/DECISIONS.md section 29.
--
-- Run it with: dbt show --select profile_claims --limit 50 --output json
-- One row per figure behind a statement in section 8. n is the count, of_n the
-- rows it is a count of, and amount the money where a figure is a sum. A
-- reference is counted as not resolving only where it is set, and of_n says
-- how many rows set it, so an empty reference column shows as 0 of 0. The
-- encounter's PAYER is the exception: section 8 says every encounter has one
-- that resolves, so a missing payer counts against it, out of every encounter.
--
-- Every lookup joins a distinct list of keys rather than the feed itself, so a
-- duplicated key in one feed cannot multiply the rows counted in another.
with claims as materialized (

    select * from {{ source('synthea', 'claims') }}

),

transactions as materialized (

    select * from {{ source('synthea', 'claims_transactions') }}

),

encounters as (

    select Id, PAYER, TOTAL_CLAIM_COST from {{ source('synthea', 'encounters') }}

),

claim_ids as (select distinct Id from claims),
encounter_ids as (select distinct Id from encounters),
patient_ids as (select distinct Id from {{ source('synthea', 'patients') }}),
provider_ids as (select distinct Id from {{ source('synthea', 'providers') }}),
payer_ids as (select distinct Id from {{ source('synthea', 'payers') }}),

claim_keys as (

    select
        count(*)                                                    as claim_rows,
        count(distinct c.Id)                                        as distinct_ids,
        count(*) - count(c.Id)                                      as null_ids,
        count(c.PATIENTID)                                          as with_patient,
        count(c.PATIENTID) - count(p.Id)                            as unresolved_patient,
        count(c.PROVIDERID)                                         as with_provider,
        count(c.PROVIDERID) - count(pr.Id)                          as unresolved_provider,
        count(c.REFERRINGPROVIDERID)                                as with_referring,
        count(c.REFERRINGPROVIDERID) - count(rp.Id)                 as unresolved_referring,
        count(c.SUPERVISINGPROVIDERID)                              as with_supervising,
        count(c.SUPERVISINGPROVIDERID) - count(sp.Id)               as unresolved_supervising,
        count(c.APPOINTMENTID)                                      as with_encounter,
        count(c.APPOINTMENTID) - count(e.Id)                        as unresolved_encounter,
        count(*) filter (where c.PRIMARYPATIENTINSURANCEID = '0')   as self_pay_sentinel
    from claims c
    left join patient_ids p on c.PATIENTID = p.Id
    left join provider_ids pr on c.PROVIDERID = pr.Id
    left join provider_ids rp on c.REFERRINGPROVIDERID = rp.Id
    left join provider_ids sp on c.SUPERVISINGPROVIDERID = sp.Id
    left join encounter_ids e on c.APPOINTMENTID = e.Id

),

transaction_keys as (

    select
        count(*)                                                    as transaction_rows,
        count(distinct t.ID)                                        as distinct_ids,
        count(*) - count(t.ID)                                      as null_ids,
        count(t.PATIENTID)                                          as with_patient,
        count(t.PATIENTID) - count(p.Id)                            as unresolved_patient,
        count(t.PROVIDERID)                                         as with_provider,
        count(t.PROVIDERID) - count(pr.Id)                          as unresolved_provider,
        count(t.SUPERVISINGPROVIDERID)                              as with_supervising,
        count(t.SUPERVISINGPROVIDERID) - count(sp.Id)               as unresolved_supervising,
        count(t.APPOINTMENTID)                                      as with_encounter,
        count(t.APPOINTMENTID) - count(e.Id)                        as unresolved_encounter,
        count(t.CLAIMID)                                            as with_claim,
        count(t.CLAIMID) - count(c.Id)                              as unresolved_claim
    from transactions t
    left join patient_ids p on t.PATIENTID = p.Id
    left join provider_ids pr on t.PROVIDERID = pr.Id
    left join provider_ids sp on t.SUPERVISINGPROVIDERID = sp.Id
    left join encounter_ids e on t.APPOINTMENTID = e.Id
    left join claim_ids c on t.CLAIMID = c.Id

),

-- One row per encounter. count(c.APPOINTMENTID) counts the claim rows joined,
-- so a claim with a null Id still counts. A null claim type is a value of its
-- own here, so an encounter mixing a null with a type counts as mixing two.
claims_per_encounter as (

    select
        e.Id,
        count(c.APPOINTMENTID)                                      as claim_count,
        count(distinct coalesce(c.HEALTHCARECLAIMTYPEID1, '(null)')) filter (where c.APPOINTMENTID is not null)
                                                                    as primary_type_count,
        count(distinct coalesce(c.HEALTHCARECLAIMTYPEID2, '(null)')) filter (where c.APPOINTMENTID is not null)
                                                                    as secondary_type_count
    from encounter_ids e
    left join claims c on c.APPOINTMENTID = e.Id
    group by e.Id

),

transaction_types as (

    select
        TYPE,
        count(*)                                                    as type_rows,
        count(AMOUNT)                                               as with_amount,
        count(PAYMENTS)                                             as with_payments,
        count(TRANSFERS)                                            as with_transfers,
        sum(cast(AMOUNT as decimal(18, 2)))                         as amount_total
    from transactions
    group by TYPE

),

figures (sort, figure, n, of_n, amount) as (

    select 1, 'claims', claim_rows, null, null from claim_keys
    union all select 2, 'claims with a distinct Id', distinct_ids, claim_rows, null from claim_keys
    union all select 3, 'claims with a null Id', null_ids, claim_rows, null from claim_keys
    union all select 4, 'claim transactions', transaction_rows, null, null from transaction_keys
    union all select 5, 'claim transactions with a distinct ID', distinct_ids, transaction_rows, null from transaction_keys
    union all select 6, 'claim transactions with a null ID', null_ids, transaction_rows, null from transaction_keys
    union all select 7, 'claims whose PATIENTID does not resolve', unresolved_patient, with_patient, null from claim_keys
    union all select 8, 'claims whose PROVIDERID does not resolve', unresolved_provider, with_provider, null from claim_keys
    union all select 9, 'claims whose REFERRINGPROVIDERID does not resolve', unresolved_referring, with_referring, null from claim_keys
    union all select 10, 'claims whose SUPERVISINGPROVIDERID does not resolve', unresolved_supervising, with_supervising, null from claim_keys
    union all select 11, 'claims whose APPOINTMENTID does not resolve to an encounter', unresolved_encounter, with_encounter, null from claim_keys
    union all select 12, 'claim transactions whose PATIENTID does not resolve', unresolved_patient, with_patient, null from transaction_keys
    union all select 13, 'claim transactions whose PROVIDERID does not resolve', unresolved_provider, with_provider, null from transaction_keys
    union all select 14, 'claim transactions whose SUPERVISINGPROVIDERID does not resolve', unresolved_supervising, with_supervising, null from transaction_keys
    union all select 15, 'claim transactions whose APPOINTMENTID does not resolve to an encounter', unresolved_encounter, with_encounter, null from transaction_keys
    union all select 16, 'claim transactions whose CLAIMID does not resolve', unresolved_claim, with_claim, null from transaction_keys
    union all select 17, 'encounters with no claim', count(*) filter (where claim_count = 0), count(*), null from claims_per_encounter
    union all select 18, 'encounters with exactly one claim', count(*) filter (where claim_count = 1), count(*), null from claims_per_encounter
    union all select 19, 'most claims on one encounter', max(claim_count), null, null from claims_per_encounter
    union all select 20, 'encounters whose claims carry more than one HEALTHCARECLAIMTYPEID1', count(*) filter (where primary_type_count > 1), count(*), null from claims_per_encounter
    union all select 21, 'encounters whose claims carry more than one HEALTHCARECLAIMTYPEID2', count(*) filter (where secondary_type_count > 1), count(*), null from claims_per_encounter
    union all select 22, 'claim transactions typed ' || coalesce(TYPE, '(null)'), type_rows, (select transaction_rows from transaction_keys), null from transaction_types
    union all select 23, 'PAYMENT transactions with an AMOUNT', with_amount, type_rows, null from transaction_types where TYPE = 'PAYMENT'
    union all select 24, 'PAYMENT transactions with PAYMENTS', with_payments, type_rows, null from transaction_types where TYPE = 'PAYMENT'
    union all select 25, 'TRANSFEROUT transactions with an AMOUNT', with_amount, type_rows, null from transaction_types where TYPE = 'TRANSFEROUT'
    union all select 26, 'TRANSFEROUT transactions with TRANSFERS', with_transfers, type_rows, null from transaction_types where TYPE = 'TRANSFEROUT'
    union all select 27, 'claims whose PRIMARYPATIENTINSURANCEID is the self-pay sentinel 0', self_pay_sentinel, claim_rows, null from claim_keys
    union all select 28, 'encounters whose PAYER is missing or does not resolve', count(*) - count(p.Id), count(*), null from encounters e left join payer_ids p on e.PAYER = p.Id
    union all select 29, 'CHARGE transactions, AMOUNT summed', type_rows, null, amount_total from transaction_types where TYPE = 'CHARGE'
    union all select 30, 'encounters, TOTAL_CLAIM_COST summed', count(*), null, sum(cast(TOTAL_CLAIM_COST as decimal(18, 2))) from encounters

)

select figure, n, of_n, amount
from figures
order by sort, figure
