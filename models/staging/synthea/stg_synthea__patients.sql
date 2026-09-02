-- Staging: one row per Synthea patient, renamed to snake_case and typed.
-- Source columns are all text (see _synthea__sources.yml), so every cast
-- below is deliberate. SSN, DRIVERS, and PASSPORT are excluded: no downstream
-- model needs them and a real EHR feed would leave them out at ingest.

with source as (

    select * from {{ source('synthea', 'patients') }}

),

renamed as (

    select
        -- identifiers
        "Id"                                        as patient_id,

        -- dates
        cast("BIRTHDATE" as date)                   as birth_date,
        cast("DEATHDATE" as date)                   as death_date,

        -- name
        "PREFIX"                                    as name_prefix,
        "FIRST"                                     as first_name,
        "LAST"                                      as last_name,
        "SUFFIX"                                    as name_suffix,
        "MAIDEN"                                    as maiden_name,

        -- demographics
        "MARITAL"                                   as marital_status,
        "RACE"                                      as race,
        "ETHNICITY"                                 as ethnicity,
        "GENDER"                                    as gender,
        "BIRTHPLACE"                                as birthplace,

        -- address; ZIP stays text to keep leading zeros
        "ADDRESS"                                   as street_address,
        "CITY"                                      as city,
        "STATE"                                     as state,
        "COUNTY"                                    as county,
        "ZIP"                                       as zip_code,
        cast("LAT" as double)                       as latitude,
        cast("LON" as double)                       as longitude,

        -- lifetime cost totals; the CSV carries float noise, so round to cents
        cast("HEALTHCARE_EXPENSES" as decimal(18, 2)) as healthcare_expenses,
        cast("HEALTHCARE_COVERAGE" as decimal(18, 2)) as healthcare_coverage

    from source

)

select * from renamed
