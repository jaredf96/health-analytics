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
        utilization                                             as lifetime_encounter_count
    from organizations

)

select * from cleaned
