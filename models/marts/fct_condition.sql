-- Condition fact, one row per condition recorded for a patient at an
-- encounter, 38,094 rows. The feed supplies no key column, so the grain is the
-- combination of patient_id, encounter_id and condition_code, the same grain
-- the staging model carries and the same one docs/DECISIONS.md section 10
-- settled. This model adds measures and foreign keys and filters nothing,
-- which tests/assert_condition_fact_matches_staging_grain.sql asserts.
--
-- It is the second fact in the star, and it builds no dimension of its own
-- except dim_condition. Patients and dates are the conformed ones
-- fct_encounter already uses, and the encounter itself is referenced rather
-- than re-described. dim_date is joined twice, once for the start of the
-- condition and once for its end, which is why the two keys are named for
-- their roles rather than both being date_id.
--
-- Measures added here rather than in staging, where derived columns are not
-- allowed: duration_days, is_open, days_from_encounter_start and
-- patient_age_years. patient_age_years is capped at 90 for the same reason it
-- is on fct_encounter: dim_patient aggregates ages over 89 into a single
-- category and withholds the year elements, and a second fact must not become
-- the way back to them. docs/DECISIONS.md sections 19 and 22.

with conditions as (

    select * from {{ ref('stg_synthea__conditions') }}

),

patients as (

    select patient_id, birth_date from {{ ref('stg_synthea__patients') }}

),

encounters as (

    select encounter_id, started_at from {{ ref('stg_synthea__encounters') }}

),

joined as (

    select
        -- grain, three columns because the feed supplies no key
        c.patient_id,
        c.encounter_id,
        c.condition_code,

        -- foreign keys, dim_date twice in two roles
        cast(strftime(c.started_date, '%Y%m%d') as integer)             as start_date_id,
        cast(strftime(c.stopped_date, '%Y%m%d') as integer)             as stop_date_id,

        -- clinical period
        c.started_date,
        c.stopped_date,
        date_diff('day', c.started_date, c.stopped_date)                as duration_days,
        c.stopped_date is null                                          as is_open,

        -- The condition date and the date of the encounter that recorded it
        -- are not the same date on 7,625 of 38,094 rows, so the two are not
        -- interchangeable and this says by how much they differ.
        date_diff('day', cast(e.started_at as date), c.started_date)    as days_from_encounter_start,

        -- age at onset, capped at 90 to match dim_patient
        case
            when {{ completed_years('p.birth_date', 'c.started_date') }} >= 90
                then 90
            else {{ completed_years('p.birth_date', 'c.started_date') }}
        end                                                             as patient_age_years

    from conditions c
    inner join patients p
        on c.patient_id = p.patient_id
    inner join encounters e
        on c.encounter_id = e.encounter_id

)

select * from joined
