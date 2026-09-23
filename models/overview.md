{% docs __overview__ %}
# health_analytics

A dbt project over synthetic electronic health record data from
[Synthea](https://synthetichealth.github.io/synthea/), MITRE's synthetic
patient generator: staged source feeds, a star schema whose facts share
conformed dimensions, a data-quality test suite, and CI that builds all of it
and publishes this site on every push to `main`. The data is entirely
artificial. There is no PHI here and no real person is represented.

Start with `fct_encounter`, one row per encounter, and `fct_condition`, one
row per condition recorded for a patient at an encounter, and the dimensions
they share, `dim_patient` and `dim_date`. The model pages carry column
descriptions and tests, and the lineage graph shows what each model is built
from.

The README, the decision log and the source are at
[github.com/jaredf96/health-analytics](https://github.com/jaredf96/health-analytics).

By Jared Fulk, [@jaredf96](https://github.com/jaredf96). Released under the MIT
License.
{% enddocs %}
