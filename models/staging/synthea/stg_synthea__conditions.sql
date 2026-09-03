-- Staging: one row per condition recorded for a patient at an encounter,
-- renamed to snake_case and typed. Source columns are all text (see
-- _synthea__sources.yml), so every cast below is deliberate. The file has no
-- key column; patient_id, encounter_id and condition_code together identify a
-- row, which tests/assert_condition_grain_is_unique.sql asserts.

with source as (

    select * from {{ source('synthea', 'conditions') }}

),

renamed as (

    select
        -- identifiers
        "PATIENT"                  as patient_id,
        "ENCOUNTER"                as encounter_id,

        -- clinical period
        cast("START" as date)      as started_date,
        cast("STOP" as date)       as stopped_date,

        -- what the condition was
        "CODE"                     as condition_code,
        "DESCRIPTION"              as condition_description

    from source

)

select * from renamed
