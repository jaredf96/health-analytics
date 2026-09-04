-- Patient dimension, de-identified to the HIPAA Safe Harbor standard.
-- docs/DECISIONS.md sections 12, 19 and 22 record why and what it costs. In
-- short: names, street address, city, county, coordinates and full dates never
-- leave staging; dates are reduced to the year, ZIP to its first three digits
-- with the seventeen low-population prefixes zeroed, and everyone over 89 is
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

conditions as (

    select * from {{ ref('stg_synthea__conditions') }}

),

-- Every date the marts publish about a patient, one row per date. Safe Harbor
-- suppresses the date elements indicative of an age over 89, so the test has
-- to be the greatest age this data can reveal, not the age at any one event. A
-- living patient with encounters in 2021 and a birth year of 1917 is over 89
-- just as plainly as a deceased one.
--
-- Every one of these dates is listed rather than the obvious one per feed,
-- because the obvious one is not always the latest. The death date does not
-- close the record: 165 encounters start and 168 end after the patient's
-- recorded death, by up to 14 days, which is the defect section 15 warns
-- about rather than filters. An encounter's end is not always within a day of
-- its start: 27 of them end later than that patient's last encounter began, by
-- up to 11 days, and three run longer than a year. And a condition outlives
-- the visit that recorded it, so 129 stop after the patient's last encounter,
-- by up to 69 days.
--
-- The rule is therefore the maximum over all of them. Anything narrower is
-- true only while no date happens to cross a birthday, which is not a rule.
-- docs/DECISIONS.md section 22.
published_dates as (

    select patient_id, death_date                           as published_date
    from patients
    where death_date is not null

    union all

    select patient_id, cast(started_at as date)             as published_date
    from encounters

    union all

    select patient_id, cast(stopped_at as date)             as published_date
    from encounters

    union all

    select patient_id, started_date                         as published_date
    from conditions

    union all

    select patient_id, stopped_date                         as published_date
    from conditions
    where stopped_date is not null

),

last_seen as (

    select
        patient_id,
        max(published_date)                                 as last_published_date
    from published_dates
    group by patient_id

),

-- Fallback for a patient no fact mentions and who has no recorded death.
-- Using the last date in the dataset is the conservative choice: it assumes
-- the patient was alive for the whole window rather than treating the age as
-- unknowable. Nothing here reads the clock, so a rebuild produces the same
-- rows.
data_end as (

    select max(published_date)                              as last_date
    from published_dates

),

attained as (

    select
        p.*,
        -- The death date is one of the published dates rather than a
        -- short circuit ahead of them, because dates after death exist here.
        {{ completed_years(
            'p.birth_date',
            'coalesce(l.last_published_date, d.last_date)'
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
