-- Staging: one row per Synthea encounter, renamed to snake_case and typed.
-- Source columns are all text (see _synthea__sources.yml), so every cast
-- below is deliberate. START and STOP arrive as ISO 8601 in UTC with a Z
-- suffix; they are cast to timestamp, which keeps the UTC wall clock and
-- makes the build independent of the machine's time zone.

with source as (

    select * from {{ source('synthea', 'encounters') }}

),

renamed as (

    select
        -- identifiers
        "Id"                                          as encounter_id,
        "PATIENT"                                     as patient_id,
        "ORGANIZATION"                                as organization_id,
        "PROVIDER"                                    as provider_id,
        "PAYER"                                       as payer_id,

        -- timing, UTC
        cast("START" as timestamp)                    as started_at,
        cast("STOP" as timestamp)                     as stopped_at,

        -- what the visit was
        "ENCOUNTERCLASS"                              as encounter_class,
        "CODE"                                        as encounter_code,
        "DESCRIPTION"                                 as encounter_description,
        "REASONCODE"                                  as reason_code,
        "REASONDESCRIPTION"                           as reason_description,

        -- money; the CSV carries float noise, so round to cents
        cast("BASE_ENCOUNTER_COST" as decimal(18, 2)) as base_encounter_cost,
        cast("TOTAL_CLAIM_COST" as decimal(18, 2))    as total_claim_cost,
        cast("PAYER_COVERAGE" as decimal(18, 2))      as payer_coverage

    from source

)

select * from renamed
