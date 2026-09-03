-- Provider dimension. The staging model's address columns repeat the employing
-- organization's address rather than a clinician's own, so they are dropped
-- here: geography belongs to dim_organization, and duplicating it would invite
-- two answers to the same question. Join through organization_id.

with providers as (

    select * from {{ ref('stg_synthea__providers') }}

),

shaped as (

    select
        provider_id,
        organization_id,
        provider_name,
        gender,
        specialty,
        utilization as lifetime_encounter_count
    from providers

)

select * from shaped
