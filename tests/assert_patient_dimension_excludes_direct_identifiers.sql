-- Singular test: dim_patient is de-identified to HIPAA Safe Harbor, so the
-- columns that carry a name, a street, a sub-state geography, a coordinate or
-- a full date must not exist on it. This guards the rule in
-- docs/DECISIONS.md section 12 against a later edit that quietly adds one back.
-- Returns the offending column names; the test passes when it returns none.
{% set forbidden_columns = [
    'first_name', 'last_name', 'maiden_name', 'name_prefix', 'name_suffix',
    'birth_date', 'death_date', 'birthplace',
    'street_address', 'city', 'county', 'zip_code', 'latitude', 'longitude'
] %}

select column_name
from information_schema.columns
where table_schema = '{{ ref('dim_patient').schema }}'
  and table_name = '{{ ref('dim_patient').identifier }}'
  and column_name in ({{ "'" ~ forbidden_columns | join("', '") ~ "'" }})
