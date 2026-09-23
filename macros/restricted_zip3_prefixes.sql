{#
    The seventeen three-digit ZIP prefixes HHS requires to be zeroed because
    their population is 20,000 or fewer. None of them appear in this sample,
    which is entirely Massachusetts (010 through 028), so the rule is inert
    here. It is written anyway: a rule that only exists when it fires is not a
    rule. The list derives from the census tabulation HHS published with the
    guidance, and the regulation binds to current census data, so this is a
    lookup that has to be maintained rather than a constant.

    dim_patient applies the list and
    tests/assert_patient_zip3_is_a_permitted_prefix.sql checks against it, so it
    lives here once rather than in both.
#}

{% macro restricted_zip3_prefixes() %}
    {{ return([
        '036', '059', '063', '102', '203', '556', '692', '790', '821',
        '823', '830', '831', '878', '879', '884', '890', '893'
    ]) }}
{% endmacro %}
