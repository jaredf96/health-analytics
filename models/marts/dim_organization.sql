-- Organization dimension. Safe Harbor governs patient data, not a directory of
-- care organizations, so the full address stays. The only rule applied here
-- collapses the runs of whitespace Synthea leaves inside organization names.

with organizations as (

    select * from {{ ref('stg_synthea__organizations') }}

),

cleaned as (

    select
        organization_id,
        trim(regexp_replace(organization_name, '\s+', ' ', 'g')) as organization_name,
        street_address,
        city,
        state,
        zip_code,
        latitude,
        longitude,
        phone,
        -- Synthea's own UTILIZATION figure, kept because it describes the
        -- directory faithfully. It counts every claim-bearing contact and
        -- disagrees with a count of fct_encounter rows on 1,020 of 1,122
        -- organizations, by up to 28 times, so it is named as what it is.
        utilization                                             as source_reported_utilization
    from organizations

)

select * from cleaned
