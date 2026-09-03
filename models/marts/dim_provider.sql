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
        -- Synthea's own UTILIZATION figure. As on dim_organization it does
        -- not equal a count of fct_encounter rows: it disagrees on 1,021
        -- of 1,123 providers, so it keeps the source's name.
        utilization as source_reported_utilization
    from providers

)

select * from shaped
