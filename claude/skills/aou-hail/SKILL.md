---
name: aou-hail
description: Hail on the All of Us Researcher Workbench - initialization with requester pays, reading MatrixTables/VDS, filtering, sample QC joins (ancestry, relatedness), GWAS with logistic/linear regression, exporting, Dataproc sizing, and common errors. Use for any Hail code against AoU genomic data.
---

# Hail on AoU

## Where to run

- **JupyterLab VM (here)**: Hail runs Spark in local mode. That's fine for `describe()`,
  `clinvar`, one small interval, or tiny subsets.
- **Dataproc app** (create it in the Workbench UI, choose Hail): use it for real work. Startup takes
  ~10 min. Mounts are under `/home/dataproc/workspace/`. To pause it, first scale secondary
  workers to 0. Stop is only a pause and still bills, so delete the app when you're done.

Suggested Dataproc sizes from the tutorials:

| Workload | Primary | Workers | Secondary |
| --- | --- | --- | --- |
| Init / exploration | n2-standard-4 | 2 × n2-standard-4 | 0 |
| Single-variant on MT/VDS | n2-standard-16 | 2 × n2-standard-4 | 2–10 × n2-standard-4 |
| Interval-based, medium | n2-standard-16 | 10 × n2-standard-8 | 20 × n2-standard-8 |

Keep preemptible/secondary workers low during shuffle-heavy steps (joins, `group_rows_by`,
`aggregate`, sort, repartition).

## Init (once per session)

```python
import os, hail as hl
hl.init(gcs_requester_pays_configuration=os.environ["GOOGLE_PROJECT"])
hl.default_reference(new_default_reference="GRCh38")
```

## Load

```python
mt  = hl.read_matrix_table(os.environ["WGS_ACAF_THRESHOLD_SPLIT_HAIL_PATH"])   # or EXOME / CLINVAR
vds = hl.vds.read_vds(os.environ["WGS_VDS_PATH"])
arr = hl.read_matrix_table(os.environ["MICROARRAY_HAIL_STORAGE_PATH"], _load_refs=False)
vcf = hl.import_vcf([...], force_bgz=True, reference_genome="GRCh38")
```

Filter early, and always to intervals first:
```python
mt = hl.filter_intervals(mt, [hl.parse_locus_interval("chr20", reference_genome="GRCh38")])
# VDS: hl.vds.filter_chromosomes(vds, keep=["chr20"]) then hl.vds.filter_intervals(...)
```

## Standard GWAS recipe (from 02.5_Hail_part2_GWAS)

```python
aux = f"{os.environ['CDR_STORAGE_PATH']}/wgs/short_read/snpindel/aux"
pheno = hl.import_table(f"{os.environ['WORKSPACE_BUCKET']}/data/phenotypes.tsv",
                        types={"person_id": hl.tstr}, impute=True, key="person_id")
related = hl.import_table(f"{aux}/relatedness/relatedness_flagged_samples.tsv", key="sample_id")
anc = hl.import_table(f"{aux}/ancestry/ancestry_preds.tsv", key="research_id", impute=True,
                      types={"research_id": hl.tstr, "pca_features": hl.tarray(hl.tfloat)})

mt = mt.semi_join_cols(pheno)
mt = mt.annotate_cols(pheno=pheno[mt.s], anc=anc[mt.s])
mt = mt.anti_join_cols(related)
mt = hl.variant_qc(mt)
mt = mt.filter_rows((hl.min(mt.variant_qc.AF) > 0.01) & (mt.variant_qc.p_value_hwe > 1e-10))

gwas = hl.logistic_regression_rows(
    test="wald", y=mt.pheno.has_disease, x=mt.GT.n_alt_alleles(),
    covariates=[1.0, mt.pheno.is_male, *[mt.anc.pca_features[i] for i in range(10)]])
gwas.flatten().export(f"{os.environ['WORKSPACE_BUCKET']}/results/gwas.tsv.bgz")
```

Phenotype prep (cohort SQL → TSV keyed by `person_id` as a string) belongs in BigQuery. See the
`aou-cdr-bigquery` skill. Restrict the cohort to `has_whole_genome_variant = 1`. Use
`hl.linear_regression_rows` for quantitative traits. To plot, run `hl.plot.manhattan(gwas.p_value)`
and `hl.plot.qq(...)`, then save to HTML with bokeh `output_file` and `save`.

## Subsetting and export

`~/workspace/aou-tutorial-notebooks/03_Getting_Started_with_Genomic_Data/06_Genomic_Data_Extraction/genomics_utils.py`
has tested helpers for this: `load_cohort_table`, `random_sample_person_ids`,
`subset_matrix_table_by_person_ids`, `filter_vds_by_chromosome`, `filter_vds_by_intervals`,
`filter_vds_by_samples_auto`, `vds_to_dense_mt`, `recompute_call_stats`, `drop_fields`, and
`export_matrix_table_to_vcf`. Read it and import from it rather than rewriting them.

Always **write a MatrixTable first** (`mt.write(path, overwrite=True)` or `mt.checkpoint(path)`),
then export VCF/PLINK/BGEN from that MT. Direct export from a long lazy pipeline is slow and fails
often. After subsetting samples, recompute AC/AF/AN and drop AC=0 sites.

## Practical tips and errors

- `.count()`, `.aggregate()`, `.show()`, and `.summarize()` trigger full computation. Use them on
  test subsets and comment them out for full runs.
- **OOM / executor lost**: increase node memory, checkpoint, shrink the subset, use fewer
  preemptibles.
- **`filter_intervals` returns nothing**: you passed chromosome names without the `chr` prefix,
  or forgot `reference_genome="GRCh38"`.
- **Requester-pays 401/403**: `hl.init` is missing `gcs_requester_pays_configuration`.
- Hail logs (`hail-*.log`) land in the working directory. Don't leave them on the mounted tutorial
  bucket, and gzip them or move them to `$WORKSPACE_BUCKET`.
