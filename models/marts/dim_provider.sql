-- Provider dimension. The staging model's address columns repeat the employing
-- organization's address rather than a clinician's own, so they are dropped
-- here: geography belongs to dim_organization, and duplicating it would invite
-- two answers to the same question. Join through organization_id.
--
-- Note before building anything on specialty: Synthea assigns every encounter
-- to a GENERAL PRACTICE clinician, so only 1,123 of these 5,056 rows are ever
-- referenced by the fact and only one of the 63 specialties is. The column is
-- kept because it describes the directory faithfully, not because encounter
-- analysis can use it.

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
