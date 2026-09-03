-- Staging: one row per care organization, renamed to snake_case and typed.
-- Source columns are all text (see _synthea__sources.yml), so every cast
-- below is deliberate. ZIP stays text: it arrives in three shapes and none
-- of them survive a numeric cast intact.

with source as (

    select * from {{ source('synthea', 'organizations') }}

),

renamed as (

    select
        -- identifiers
        "Id"                                as organization_id,
        "NAME"                              as organization_name,

        -- address; ZIP stays text to keep leading zeros and ZIP+4
        "ADDRESS"                           as street_address,
        "CITY"                              as city,
        "STATE"                             as state,
        "ZIP"                               as zip_code,
        cast("LAT" as double)               as latitude,
        cast("LON" as double)               as longitude,
        "PHONE"                             as phone,

        -- lifetime totals
        cast("REVENUE" as decimal(18, 2))   as revenue,
        cast("UTILIZATION" as integer)      as utilization

    from source

)

select * from renamed
