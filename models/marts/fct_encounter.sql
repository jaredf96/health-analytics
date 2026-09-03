-- Encounter fact, one row per encounter. The grain is the staging grain: this
-- model adds measures and foreign keys and filters nothing, which
-- tests/assert_encounter_fact_matches_staging_grain.sql asserts.
--
-- Measures added here rather than in staging, where derived columns are not
-- allowed: uncovered_amount, duration_minutes, patient_age_years, and
-- condition_count. patient_age_years is capped at 90 to match the Safe Harbor
-- rule dim_patient applies, so the fact cannot be used to recover an age the
-- dimension deliberately hides.

with encounters as (

    select * from {{ ref('stg_synthea__encounters') }}

),

patients as (

    select patient_id, birth_date from {{ ref('stg_synthea__patients') }}

),

conditions_per_encounter as (

    select
        encounter_id,
        count(*) as condition_count
    from {{ ref('stg_synthea__conditions') }}
    group by encounter_id

),

joined as (

    select
        -- degenerate key
        e.encounter_id,

        -- foreign keys
        cast(strftime(cast(e.started_at as date), '%Y%m%d') as integer) as date_id,
        e.patient_id,
        e.organization_id,
        e.provider_id,
        e.payer_id,
        e.encounter_code,

        -- degenerate dimensions
        e.encounter_class,
        e.reason_code,
        e.reason_description,

        -- timing
        e.started_at,
        e.stopped_at,
        date_diff('minute', e.started_at, e.stopped_at)                 as duration_minutes,

        -- age at the encounter, capped at 90 to match dim_patient
        case
            when {{ completed_years('p.birth_date', 'cast(e.started_at as date)') }} >= 90
                then 90
            else {{ completed_years('p.birth_date', 'cast(e.started_at as date)') }}
        end                                                             as patient_age_years,

        -- clinical volume
        coalesce(c.condition_count, 0)                                  as condition_count,

        -- money
        e.base_encounter_cost,
        e.total_claim_cost,
        e.payer_coverage,
        -- Billed minus what the payer covered. In a real revenue cycle
        -- this residual is dominated by contractual adjustments rather
        -- than by patient liability, so it is named for what it measures.
        e.total_claim_cost - e.payer_coverage                           as uncovered_amount

    from encounters e
    inner join patients p
        on e.patient_id = p.patient_id
    left join conditions_per_encounter c
        on e.encounter_id = c.encounter_id

)

select * from joined
