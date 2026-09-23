-- Encounter fact, one row per encounter. The grain is the staging grain: this
-- model adds measures and foreign keys and filters nothing, which
-- tests/assert_encounter_fact_matches_staging_grain.sql asserts.
--
-- Measures added here rather than in staging, where derived columns are not
-- allowed: uncovered_amount, duration_minutes, length_of_stay_days,
-- patient_age_years, and condition_count. patient_age_years is withheld, not
-- capped, for the patients the over-89 rule in dim_patient protects, and the
-- comment on the column says why. The fact keeps exact service timestamps, so
-- the project makes no Safe Harbor claim for this model.
-- docs/DECISIONS.md sections 19 and 27.

with encounters as (

    select * from {{ ref('stg_synthea__encounters') }}

),

patients as (

    select patient_id, birth_date from {{ ref('stg_synthea__patients') }}

),

-- Who the over-89 rule protects. Taken from dim_patient rather than recomputed,
-- so the cohort the fact suppresses and the cohort the dimension aggregates are
-- one definition and cannot drift apart. dim_patient reads only staging, so
-- this ref is not a cycle.
protected as (

    select patient_id from {{ ref('dim_patient') }} where is_age_90_or_older

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
        -- Completed minutes, the whole minutes of elapsed time.
        -- date_diff('minute', ...) counts minute boundaries crossed instead,
        -- which reads one over whenever the stop's seconds fall before the
        -- start's; docs/DECISIONS.md section 18 is the same distinction for age.
        date_diff('second', e.started_at, e.stopped_at) // 60           as duration_minutes,

        -- Length of stay, inpatient only, counted in UTC midnights: the
        -- discharge date less the admission date, both taken on the UTC clock
        -- of the feed's timestamps. It is not duration_minutes rescaled; the
        -- two disagree on 158 of the 1,728 inpatient encounters, because a
        -- stay is counted in nights rather than in elapsed hours. Null on every
        -- other class, where the measure has no meaning, and
        -- tests/assert_length_of_stay_is_inpatient_only.sql asserts that.
        -- No coalesce guards a missing discharge: stopped_at is not_null in
        -- staging and here, so a feed that ever carried an open stay would
        -- fail that test rather than quietly measure the stay as zero.
        case
            when e.encounter_class = 'inpatient'
                then date_diff('day', cast(e.started_at as date), cast(e.stopped_at as date))
        end                                                             as length_of_stay_days,

        -- Age at the encounter, withheld entirely for the patients the over-89
        -- rule protects. A cap is not enough here: an exact age below 90 beside
        -- an exact service date bounds the birth year, and a second published
        -- date for the same patient turns that bound back into an age over 89,
        -- without reading dim_patient at all. Stamping 90 on those rows is
        -- worse than the cap rather than better, because a 90 against an
        -- earlier date is a stronger anchor than the true age was.
        -- docs/DECISIONS.md section 27.
        case
            when pr.patient_id is null
                then {{ completed_years('p.birth_date', 'cast(e.started_at as date)') }}
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
    left join protected pr
        on e.patient_id = pr.patient_id
    left join conditions_per_encounter c
        on e.encounter_id = c.encounter_id

)

select * from joined
