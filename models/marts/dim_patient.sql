-- Patient dimension, de-identified to the HIPAA Safe Harbor standard.
-- docs/DECISIONS.md section 12 records why and what it costs. In short:
-- names, street address, city, county, coordinates and full dates never leave
-- staging; dates are reduced to the year, ZIP to its first three digits with
-- the seventeen low-population prefixes zeroed, and any age over 89 is
-- reported as 90. The data is synthetic, so nothing here protects a real
-- person; the point is that the rule is written down, applied in one place,
-- and enforced by a test rather than by trust.

-- The seventeen three-digit ZIP prefixes HHS requires to be zeroed because
-- their population is 20,000 or fewer. None of them appear in this sample,
-- which is entirely Massachusetts (010 through 028), so the rule is inert
-- here. It is written anyway: a rule that only exists when it fires is not a
-- rule.
{% set restricted_zip3 = [
    '036', '059', '063', '102', '203', '556', '692', '790', '821',
    '823', '830', '831', '878', '879', '884', '890', '893'
] %}

with patients as (

    select * from {{ ref('stg_synthea__patients') }}

),

deidentified as (

    select
        patient_id,

        -- dates reduced to the year
        year(birth_date)                                    as birth_year,
        year(death_date)                                    as death_year,
        death_date is not null                              as is_deceased,

        -- age is capped at 90; Safe Harbor aggregates everything over 89
        case
            when death_date is null then null
            when date_diff('year', birth_date, death_date) >= 90 then 90
            else date_diff('year', birth_date, death_date)
        end                                                 as age_at_death_years,
        death_date is not null
            and date_diff('year', birth_date, death_date) >= 90 as is_age_at_death_90_or_older,

        -- demographics are not identifiers under Safe Harbor
        gender,
        race,
        ethnicity,
        marital_status,

        -- geography reduced to state and a three-digit ZIP prefix
        state,
        case
            when zip_code is null then null
            when substr(zip_code, 1, 3) in ({{ "'" ~ restricted_zip3 | join("', '") ~ "'" }}) then '000'
            else substr(zip_code, 1, 3)
        end                                                 as zip3,

        -- lifetime cost totals as Synthea recorded them for this patient
        healthcare_expenses                                 as lifetime_healthcare_expenses,
        healthcare_coverage                                 as lifetime_healthcare_coverage

    from patients

)

select * from deidentified
