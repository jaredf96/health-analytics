-- Staging: one row per insurance payer, renamed to snake_case and typed.
-- Source columns are all text (see _synthea__sources.yml), so every cast
-- below is deliberate. The lifetime totals are Synthea's own rollups across
-- the whole generated population, not a sum over this sample's encounters.

with source as (

    select * from {{ source('synthea', 'payers') }}

),

renamed as (

    select
        -- identifiers
        "Id"                                        as payer_id,
        "NAME"                                      as payer_name,

        -- headquarters address; ZIP stays text to keep leading zeros
        "ADDRESS"                                   as street_address,
        "CITY"                                      as city,
        "STATE_HEADQUARTERED"                       as headquarters_state,
        "ZIP"                                       as zip_code,
        "PHONE"                                     as phone,

        -- lifetime money totals
        cast("AMOUNT_COVERED" as decimal(18, 2))    as amount_covered,
        cast("AMOUNT_UNCOVERED" as decimal(18, 2))  as amount_uncovered,
        cast("REVENUE" as decimal(18, 2))           as revenue,

        -- lifetime counts, split by whether the payer covered the item
        cast("COVERED_ENCOUNTERS" as integer)       as covered_encounters,
        cast("UNCOVERED_ENCOUNTERS" as integer)     as uncovered_encounters,
        cast("COVERED_MEDICATIONS" as integer)      as covered_medications,
        cast("UNCOVERED_MEDICATIONS" as integer)    as uncovered_medications,
        cast("COVERED_PROCEDURES" as integer)       as covered_procedures,
        cast("UNCOVERED_PROCEDURES" as integer)     as uncovered_procedures,
        cast("COVERED_IMMUNIZATIONS" as integer)    as covered_immunizations,
        cast("UNCOVERED_IMMUNIZATIONS" as integer)  as uncovered_immunizations,
        cast("UNIQUE_CUSTOMERS" as integer)         as unique_customers,
        cast("MEMBER_MONTHS" as integer)            as member_months,

        -- average quality of life score across the payer's members
        cast("QOLS_AVG" as double)                  as quality_of_life_score_avg

    from source

)

select * from renamed
