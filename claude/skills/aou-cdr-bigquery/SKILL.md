---
name: aou-cdr-bigquery
description: Query the All of Us Curated Data Repository (OMOP CDM in BigQuery) from Python, R, or the bq CLI - demographics, conditions, drugs, measurements, surveys, wearables, zip3/SES, death, and building case/control cohorts. Use for any SQL against $WORKSPACE_CDR or its index dataset.
---

# Querying the AoU CDR

The CDR is OMOP CDM v5 plus AoU extensions, in BigQuery at `$WORKSPACE_CDR` (`project.dataset`).
Queries bill to `$GOOGLE_PROJECT`. SQL recipes are in `reference/sql-recipes.md`.

## Workflow

1. **Find concept IDs first** in `concept` (or `cb_criteria`), then query the event tables by ID.
   Don't filter event tables by name strings.
2. **Dry-run** to check cost: `bq query --dry_run --use_legacy_sql=false "$SQL"`.
3. Run it, select only the columns you need, and aggregate in SQL where you can.
4. **Count distinct `person_id`**, not rows. Mask counts of 1–20 in anything for sharing.

## Clients

Python (the tutorials' pattern):
```python
import os, pandas_gbq
CDR = os.environ["WORKSPACE_CDR"]
df = pandas_gbq.read_gbq(f"SELECT COUNT(DISTINCT person_id) n FROM `{CDR}.person`",
                         dialect="standard", progress_bar_type=None)
# Add use_bqstorage_api=True for large results; fall back to False if it errors.
```
`google.cloud.bigquery.Client(project=os.environ["GOOGLE_PROJECT"]).query(sql).to_dataframe()`
works too. If `import pandas_gbq` fails, run `~/repos/aou-claude-setup/setup.sh --only python`.

R:
```r
library(bigrquery)
CDR <- Sys.getenv("WORKSPACE_CDR")
df <- bq_table_download(bq_project_query(Sys.getenv("GOOGLE_PROJECT"),
        glue::glue("SELECT COUNT(DISTINCT person_id) n FROM `{CDR}.person`")))
```

CLI: `bq query --use_legacy_sql=false --format=csv --max_rows=50 "..."`.
Schema: `bq show --schema --format=prettyjson "${WORKSPACE_CDR/./:}.observation" | jq -r '.[].name'`.

## Map of the CDR

| Need | Table(s) | Key columns |
| --- | --- | --- |
| Demographics | `person` (+ `concept` joins), `ds_person` (names already joined), `cb_search_person` | `gender_concept_id`, `race_concept_id`, `ethnicity_concept_id`, `sex_at_birth_concept_id`, `birth_datetime` |
| Data-type flags per person | `cb_search_person` | `has_ehr_data`, `has_ppi_survey_data`, `has_physical_measurement_data`, `has_whole_genome_variant`, `has_array_data`, `has_lr_whole_genome_variant`, `has_structural_variant_data`, `has_fitbit`, `age_at_cdr`, `state_of_residence` |
| More flags (proteomics, RNA-seq) | `$WORKSPACE_CDR_INDEX.T_ENT_person` | `has_proteomics_data`, `has_rnaseq_data`, … (`id` = person_id) |
| Conditions | `condition_occurrence` | `condition_concept_id` (standard, SNOMED), `condition_source_concept_id` (ICD9CM/ICD10CM) |
| Drugs | `drug_exposure` | `drug_concept_id` (RxNorm). Roll up from ingredients with `concept_ancestor` |
| Labs and vitals | `measurement` | `measurement_concept_id` (LOINC), `value_as_number`, `unit_concept_id` |
| Procedures, visits, devices | `procedure_occurrence`, `visit_occurrence`, `device_exposure` | |
| Surveys (PPI) | `ds_survey` (easiest), or `observation` + `concept` | `question_concept_id`, `answer_concept_id`, `survey`, `question`, `answer` |
| Zip3 and socioeconomic (CT only) | `observation` (`observation_source_concept_id = 1585250`, `value_as_string`) + `zip3_ses_map` | `zip3_as_string`, `median_income`, `deprivation_index`, … |
| Death | `aou_death` ∪ `death` | `death_date`, `cause_concept_id`, `cause_source_value` |
| Wearables (Fitbit) | `activity_summary`, `heart_rate_summary`, `heart_rate_intraday`, `steps_intraday`, `sleep_*`, `device` | `person_id`, `date` |
| Ad-hoc cohort search (Cohort Builder) | `cb_search_all_events`, `cb_criteria`, `cb_criteria_ancestor` | `concept_id`, `is_standard`, `domain` |
| Vocabulary | `concept`, `concept_ancestor`, `concept_relationship`, `concept_synonym` | |
| Column docs | `ds_data_dictionary` | |

`*_ext` tables hold `src_id` (the data source, e.g. EHR site vs participant-provided). The `ds_*`
tables are the denormalized "dataset builder" versions with concept names already joined.

## Standard vs source concepts

- `*_concept_id` holds the **standard** concept (SNOMED, RxNorm, LOINC). Use it with
  `concept_ancestor` to include descendants.
- `*_source_concept_id` holds the **source** code as recorded (ICD9CM, ICD10CM, CPT4, and PPI
  for surveys). Use it to match ICD code lists exactly. Survey questions and answers live in
  `observation_source_concept_id` and `value_source_concept_id`.

## CT-only data elements

Controlled Tier has data the Registered Tier lacks or generalizes: real event dates (not
shifted), participants aged 89+, 3-digit zip and SES data, race/ethnicity subcategories (questions
1586150–1586156), living situation (1585402), military status (1585852), certain COPE COVID
items, EHR race/ethnicity/sex, and death causes. Treat all of these as especially re-identifying.

## Other datasets

- `prep_<CDR>`: preprocessed tables that back the platform tooling. Use only if asked.
- `C_V9_R3_aou_biospecimen`: biospecimen inventory.
- `C_V9_R6_offcycle_nlp`: off-cycle NLP-derived EHR data.
- `$WORKSPACE_CDR_INDEX` (`<CDR>_index_<mmddyy>`): Data Explorer / cohort-builder index (`T_ENT_*`
  entity tables, `T_ELDH_*`, `T_ECH_*`).
