-- Date dimension. The spine is anchored to the encounter data itself, from the
-- first encounter to the last, so a rebuild produces the same rows on any
-- machine on any day. Nothing in this project uses current_date, because every
-- number the README states has to be reproducible from a dbt build.

with bounds as (

    select
        cast(min(started_at) as date) as first_date,
        cast(max(started_at) as date) as last_date
    from {{ ref('stg_synthea__encounters') }}

),

spine as (

    select cast(unnest(generate_series(first_date, last_date, interval 1 day)) as date) as calendar_date
    from bounds

),

dated as (

    select
        cast(strftime(calendar_date, '%Y%m%d') as integer) as date_id,
        calendar_date,
        year(calendar_date)                                as calendar_year,
        quarter(calendar_date)                             as calendar_quarter,
        month(calendar_date)                               as calendar_month,
        monthname(calendar_date)                           as month_name,
        strftime(calendar_date, '%Y-%m')                   as year_month,
        day(calendar_date)                                 as day_of_month,
        isodow(calendar_date)                              as day_of_week,
        dayname(calendar_date)                             as day_name,
        week(calendar_date)                                as iso_week,
        isodow(calendar_date) >= 6                         as is_weekend
    from spine

)

select * from dated
