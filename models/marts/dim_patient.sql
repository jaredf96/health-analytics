-- Patient dimension, de-identified to the HIPAA Safe Harbor standard.
-- docs/DECISIONS.md sections 12 and 19 record why and what it costs. In short:
-- names, street address, city, county, coordinates and full dates never leave
-- staging; dates are reduced to the year, ZIP to its first three digits with
-- the seventeen low-population prefixes zeroed, and everyone over 89 is
-- aggregated into a single category with the year elements that would reveal
-- the age removed. The data is synthetic, so nothing here protects a real
-- person; the point is that the rule is written down, applied in one place,
-- and enforced by tests that read the data rather than by trust.

-- The seventeen three-digit ZIP prefixes HHS requires to be zeroed because
-- their population is 20,000 or fewer. None of them appear in this sample,
-- which is entirely Massachusetts (010 through 028), so the rule is inert
-- here. It is written anyway: a rule that only exists when it fires is not a
-- rule. The list derives from the census tabulation HHS published with the
-- guidance, and the regulation binds to current census data, so this is a
-- lookup that has to be maintained rather than a constant.
{% set restricted_zip3 = [
    '036', '059', '063', '102', '203', '556', '692', '790', '821',
    '823', '830', '831', '878', '879', '884', '890', '893'
] %}

with patients as (

    select * from {{ ref('stg_synthea__patients') }}

),

encounters as (

    select * from {{ ref('stg_synthea__encounters') }}

),

-- The last date on which each patient appears. Safe Harbor suppresses the
-- date elements indicative of an age over 89, so the test has to be the
-- greatest age this data can reveal about a patient, not only their age at
-- death. A living patient with encounters in 2021 and a birth year of 1917 is
-- over 89 just as plainly as a deceased one.
last_seen as (

    select
        patient_id,
        max(cast(started_at as date))                       as last_encounter_date
    from encounters
    group by patient_id

),

-- Fallback for a patient the encounter feed never mentions. Using the last
-- date in the dataset is the conservative choice: it assumes the patient was
-- alive for the whole window rather than treating the age as unknowable.
-- Nothing here reads the clock, so a rebuild produces the same rows.
data_end as (

    select max(cast(started_at as date))                    as last_date
    from encounters

),

attained as (

    select
        p.*,
        {{ completed_years(
            'p.birth_date',
            'coalesce(p.death_date, l.last_encounter_date, d.last_date)'
        ) }}                                                as max_attained_age
    from patients p
    left join last_seen l using (patient_id)
    cross join data_end d

),

deidentified as (

    select
        patient_id,

        -- Dates reduced to the year, and withheld entirely for the over-89
        -- cohort. 45 CFR 164.514(b)(2)(i)(C) removes ages over 89 together
        -- with the elements of dates, the year included, that are indicative
        -- of such an age, allowing them to be aggregated into a single
        -- category instead. Publishing the birth year beside a capped age
        -- would let one subtraction undo the cap, which is the whole reason
        -- the year goes with it.
        case
            when max_attained_age >= 90 then null
            else year(birth_date)
        end                                                 as birth_year,
        case
            when max_attained_age >= 90 then null
            else year(death_date)
        end                                                 as death_year,
        death_date is not null                              as is_deceased,

        -- The single permitted category. It replaces the year elements above
        -- rather than sitting beside them.
        max_attained_age >= 90                              as is_age_90_or_older,

        -- Age at death, capped at 90, null while the patient is alive.
        case
            when death_date is null then null
            when {{ completed_years('birth_date', 'death_date') }} >= 90 then 90
            else {{ completed_years('birth_date', 'death_date') }}
        end                                                 as age_at_death_years,

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

    from attained

)

select * from deidentified
