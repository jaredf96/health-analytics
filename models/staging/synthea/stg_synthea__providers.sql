-- Staging: one row per clinician, renamed to snake_case and typed. Source
-- columns are all text (see _synthea__sources.yml), so every cast below is
-- deliberate. The source column SPECIALITY is renamed to specialty. Address
-- columns repeat the employing organization's address, not a clinician's own.

with source as (

    select * from {{ source('synthea', 'providers') }}

),

renamed as (

    select
        -- identifiers
        "Id"                            as provider_id,
        "ORGANIZATION"                  as organization_id,
        "NAME"                          as provider_name,

        -- attributes
        "GENDER"                        as gender,
        "SPECIALITY"                    as specialty,

        -- address; ZIP stays text to keep leading zeros and ZIP+4
        "ADDRESS"                       as street_address,
        "CITY"                          as city,
        "STATE"                         as state,
        "ZIP"                           as zip_code,
        cast("LAT" as double)           as latitude,
        cast("LON" as double)           as longitude,

        -- lifetime total
        cast("UTILIZATION" as integer)  as utilization

    from source

)

select * from renamed
