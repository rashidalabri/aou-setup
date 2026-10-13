# CDR SQL recipes

`{CDR}` = `$WORKSPACE_CDR` (wrap it in backticks: `` `{CDR}.person` ``). These recipes come from
the AoU tutorial notebooks (Data 101, Hail/PLINK phenotype prep).

## Concept lookup

```sql
-- Find standard concepts by name or code
SELECT concept_id, concept_name, vocabulary_id, concept_code, domain_id, standard_concept
FROM `{CDR}.concept`
WHERE LOWER(concept_name) LIKE '%type 2 diabetes%' AND standard_concept = 'S'
ORDER BY vocabulary_id
LIMIT 50;

-- Source concepts for ICD code lists (match exact codes)
SELECT DISTINCT c.concept_id
FROM `{CDR}.concept` c
JOIN `{CDR}.condition_occurrence` co ON c.concept_id = co.condition_source_concept_id
WHERE (c.vocabulary_id = 'ICD9CM'  AND c.concept_code IN ('250.00','250.02'))
   OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code IN ('E11.9','E11.65'));

-- All descendants of a standard concept
SELECT descendant_concept_id
FROM `{CDR}.concept_ancestor`
WHERE ancestor_concept_id = 201826;   -- Type 2 diabetes mellitus (SNOMED)
```

## Drugs by ingredient (with descendants)

```sql
SELECT DISTINCT c2.concept_id
FROM `{CDR}.concept` c
JOIN `{CDR}.concept_ancestor` ca ON c.concept_id = ca.ancestor_concept_id
JOIN `{CDR}.concept` c2 ON c2.concept_id = ca.descendant_concept_id
WHERE c.concept_class_id = 'Ingredient'
  AND (LOWER(c.concept_name) LIKE '%metformin%' OR LOWER(c.concept_name) LIKE '%glipizide%');
```

## Case definition: T2D (dx and meds, excluding T1D)

```sql
SELECT p.person_id, 1 AS has_t2d
FROM `{CDR}.person` p
WHERE person_id IN (SELECT person_id FROM `{CDR}.condition_occurrence`
                    WHERE condition_source_concept_id IN UNNEST(@t2d_dx))
  AND person_id IN (SELECT person_id FROM `{CDR}.drug_exposure`
                    WHERE drug_concept_id IN UNNEST(@t2d_rx))
  AND person_id NOT IN (SELECT person_id FROM `{CDR}.condition_occurrence`
                        WHERE condition_source_concept_id IN UNNEST(@t1d_dx));
```
In Python, either interpolate `tuple(ids)` (as the tutorials do; watch out for 1-element tuples)
or pass query parameters with `google.cloud.bigquery.ArrayQueryParameter`.

## Demographics with names

```sql
SELECT p.person_id,
       g.concept_name  AS gender,
       sab.concept_name AS sex_at_birth,
       r.concept_name  AS race,
       e.concept_name  AS ethnicity,
       DATE(p.birth_datetime) AS birth_date
FROM `{CDR}.person` p
LEFT JOIN `{CDR}.concept` g   ON g.concept_id   = p.gender_concept_id
LEFT JOIN `{CDR}.concept` sab ON sab.concept_id = p.sex_at_birth_concept_id
LEFT JOIN `{CDR}.concept` r   ON r.concept_id   = p.race_concept_id
LEFT JOIN `{CDR}.concept` e   ON e.concept_id   = p.ethnicity_concept_id;
```

## Restrict to participants with WGS (or other data types)

```sql
SELECT person_id FROM `{CDR}.cb_search_person` WHERE has_whole_genome_variant = 1;
-- Or via the index dataset (also has proteomics and RNA-seq flags):
SELECT id AS person_id FROM `{CDR_INDEX}.T_ENT_person` WHERE has_whole_genome_variant = TRUE;
```
Check a flag's type with `bq show --schema` before filtering. Some are INT64 and some are BOOL.

## Survey answers (question → answer distribution)

```sql
-- Easiest: ds_survey has names already joined
SELECT question, answer, COUNT(DISTINCT person_id) AS n
FROM `{CDR}.ds_survey`
WHERE question_concept_id = 1585852
GROUP BY 1, 2 ORDER BY n DESC;

-- Raw OMOP form (handles numeric answers)
SELECT q.concept_name AS question,
       COALESCE(a.concept_name, CAST(o.value_as_number AS STRING)) AS answer,
       COUNT(DISTINCT o.person_id) AS n
FROM `{CDR}.observation` o
JOIN `{CDR}.concept` q ON q.concept_id = o.observation_source_concept_id
LEFT JOIN `{CDR}.concept` a ON a.concept_id = o.value_source_concept_id
WHERE o.observation_source_concept_id IN (1585852)
GROUP BY 1, 2 ORDER BY n DESC;
```
Answers named like "PMI: Skip" or "PMI: Prefer Not To Answer" are non-responses. Exclude them
from denominators unless you're asked to keep them.

## Measurements (latest value per person)

```sql
SELECT person_id, value_as_number, unit_concept_id, measurement_date
FROM (
  SELECT m.*, ROW_NUMBER() OVER (PARTITION BY person_id ORDER BY measurement_datetime DESC) rn
  FROM `{CDR}.measurement` m
  WHERE measurement_concept_id IN (SELECT descendant_concept_id FROM `{CDR}.concept_ancestor`
                                   WHERE ancestor_concept_id = 3004410)  -- HbA1c (LOINC 4548-4)
    AND value_as_number IS NOT NULL)
WHERE rn = 1;
```
Check `unit_concept_id`: units vary across sites.

## Zip3 and socioeconomic (CT only)

```sql
SELECT o.person_id, z.median_income, z.deprivation_index, z.fraction_poverty
FROM `{CDR}.observation` o
JOIN `{CDR}.zip3_ses_map` z ON o.value_as_string = z.zip3_as_string
WHERE o.observation_source_concept_id = 1585250;
```

## Death (both tables)

```sql
WITH d AS (
  SELECT DISTINCT person_id, death_date, cause_concept_id, cause_source_value FROM `{CDR}.aou_death`
  UNION DISTINCT
  SELECT DISTINCT person_id, death_date, cause_concept_id, cause_source_value FROM `{CDR}.death`)
SELECT d.*, c.concept_name AS cause
FROM d LEFT JOIN `{CDR}.concept` c ON c.concept_id = d.cause_concept_id;
```

## Age at CDR cutoff

```sql
SELECT person_id,
  DATE_DIFF(DATE '2025-01-01', DATE(birth_datetime), YEAR)
    - IF(FORMAT_DATE('%m%d', DATE '2025-01-01') < FORMAT_DATE('%m%d', DATE(birth_datetime)), 1, 0) AS age_at_cdr
FROM `{CDR}.person`;
```
`cb_search_person.age_at_cdr` already has this value.

## Cohort Builder style (any domain, standard or source)

```sql
SELECT DISTINCT person_id
FROM `{CDR}.cb_search_all_events`
WHERE is_standard = 0 AND concept_id IN (/* source concept ids */)
   OR is_standard = 1 AND concept_id IN (
        SELECT DISTINCT c.concept_id FROM `{CDR}.cb_criteria` c
        JOIN (SELECT CAST(id AS STRING) id FROM `{CDR}.cb_criteria`
              WHERE concept_id IN (201826) AND is_standard = 1 AND full_text LIKE '%_rank1]%') a
          ON c.path LIKE CONCAT('%.', a.id, '.%') OR c.path LIKE CONCAT('%.', a.id) OR c.path = a.id
        WHERE c.is_standard = 1 AND c.is_selectable = 1);
```
For most tasks, querying the OMOP tables with `concept_ancestor` is simpler and easier to check.
