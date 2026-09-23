-- Singular test: dim_patient publishes a ZIP only as its first three digits,
-- and a prefix HHS restricts only as 000. 45 CFR 164.514(b)(2)(i)(B) keeps the
-- initial three digits of a ZIP code only where they cover more than 20,000
-- people, and requires the rest to be changed to 000. The column test cannot
-- see a breach of this: a full ZIP published under the name zip3 passes it,
-- because it checks names. This checks the values. None of the restricted
-- prefixes occurs in this sample, so the second clause is inert here, as the
-- rule it checks is; docs/DECISIONS.md section 28.
-- Returns the offending rows; the test passes when it returns none.
{% set restricted_zip3 = restricted_zip3_prefixes() %}

-- A published ZIP that is not a three-digit prefix.
select
    patient_id,
    zip3,
    'not a three-digit prefix'                          as violation
from {{ ref('dim_patient') }}
where zip3 is not null
  and not regexp_full_match(zip3, '[0-9]{3}')

union all

-- A restricted prefix published as itself rather than as 000.
select
    patient_id,
    zip3,
    'restricted prefix published'                       as violation
from {{ ref('dim_patient') }}
where zip3 in ({{ "'" ~ restricted_zip3 | join("', '") ~ "'" }})
