{#
    Completed years between two dates: the ordinary meaning of age, where the
    birthday has to have passed for the year to count.

    DuckDB's `date_diff('year', ...)` counts calendar-year boundaries, not
    completed years. It returns 30 for a birth on 1990-12-31 and a date of
    2020-01-01, where the completed age is 29. Across `fct_encounter` the two
    readings disagree on 29,831 of 61,459 rows, so the difference is the common
    case rather than an edge case.

    Both endpoints are supplied by the caller, so this reads no clock and the
    result is reproducible from a build on any machine on any day.
#}

{% macro completed_years(start_date, end_date) %}
    (
        date_diff('year', {{ start_date }}, {{ end_date }})
        - case
            when (month({{ end_date }}), day({{ end_date }}))
                 < (month({{ start_date }}), day({{ start_date }}))
                then 1
            else 0
          end
    )
{% endmacro %}
