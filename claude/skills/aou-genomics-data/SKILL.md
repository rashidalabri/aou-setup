---
name: aou-genomics-data
description: Catalog of All of Us Controlled Tier genomic and multi-omic data (srWGS SNP/indel callsets, VDS, SVs, CRAMs, long-read WGS, microarray, RNA-seq, proteomics, ancestry/relatedness/QC auxiliary files) - where each lives, which format to choose, and how to read it with gcloud, bcftools, plink, or pandas. Use when locating or reading any genomic file.
---

# AoU genomic data (CT v9)

Root: `$CDR_STORAGE_PATH` = `gs://vwb-aou-datasets-controlled/v9`. It's **requester-pays**:
```bash
gcloud storage ls --billing-project="$GOOGLE_PROJECT" "$CDR_STORAGE_PATH/wgs/short_read/snpindel/"
gsutil -u "$GOOGLE_PROJECT" du -sh <path>          # check size before copying anything
```
There's a read-only local mount at `$AOU_CT_MOUNT/v9/...` (quote it, the path has spaces). Older
releases sit next to it (`.../v8`, `.../v7`). CRAMs are pooled across releases in
`gs://vwb-aou-datasets-controlled/pooled/wgs/cram/{v7_base,v8_base,v9_delta}`. Platform variables
already point at the common paths: `WGS_VDS_PATH`, `WGS_{EXOME,CLINVAR,ACAF_THRESHOLD}_{SPLIT,MULTI}_HAIL_PATH`,
`WGS_*_VCF_PATH`, `WGS_CRAM_MANIFEST_PATH`, `MICROARRAY_HAIL_STORAGE_PATH`, `MICROARRAY_*_MANIFEST_PATH`,
`HG38_REFERENCE_{FASTA,FAI,DICT}`. List them with `env | grep -E '^(WGS|MICROARRAY|HG38)'`.

## Which short-read callset?

| Callset | Contents | Formats under `wgs/short_read/snpindel/<callset>/` |
| --- | --- | --- |
| `exome` | variants in exonic regions | `splitMT`, `multiMT`, `vcf`, `plink_bed`, `pgen`, `bgen` |
| `clinvar` | ClinVar sites, small (good for tests) | same set |
| `acaf_threshold` | common variants: population AF > 1% or AC > 100. Largest; use for GWAS | same set plus `bed` |
| `vds/hail.vds` | full joint callset (VariantDataset), all sites | Hail VDS only. Expensive |

Start with the smallest callset that answers the question. Prefer `splitMT` (biallelic) over
`multiMT`. Only use the VDS when you need sites outside these callsets or reference blocks.
v9 file names carry a prefix, e.g. `clinvar/plink_bed/clinvar.chr21.bed` (v8 used `chr21.bed`).
CMRG is no longer a callset in v9. It now lives under `aux/cmrg`.

## Auxiliary files: `wgs/short_read/snpindel/aux/`

| Dir | Use |
| --- | --- |
| `ancestry/ancestry_preds.tsv` | predicted ancestry + `pca_features` per `research_id`. Use as GWAS covariates |
| `relatedness/relatedness_flagged_samples.tsv` | samples to drop for an unrelated set (`sample_id`) |
| `relatedness/samples_relatedness.tsv` | pairwise kinship |
| `qc/flagged_samples.tsv`, `qc/genomics_metrics.tsv`, `qc/all_samples.tsv` | sample QC |
| `pca/`, `admixture_estimates/`, `local_ancestry_inference/` | population structure |
| `pgx/` | pharmacogenomic star alleles (`high_concordance/` per gene) |
| `hla_variants/`, `mitochondria/`, `phasing/`, `cmrg/` | as named |
| `vat/` (also `snpindel/vat/`) | Variant Annotation Table: `vat_complete.bgz.tsv.gz` (+ `.tbi`, so tabix region queries work) |

Sample IDs in genomic files are the CDR `person_id` (as strings: `s` in Hail, `research_id` in
aux files, IID in plink).

## Other data types

- **Structural variants**: `wgs/short_read/structural_variants/{vcf,aux}`.
- **CRAMs**: `wgs/cram/manifest.csv` (person_id → cram path). Stream a region instead of
  downloading:
  `GCS_OAUTH_TOKEN=$(gcloud auth print-access-token) GCS_REQUESTER_PAYS_PROJECT=$GOOGLE_PROJECT samtools view -T $HG38_REFERENCE_FASTA <cram> chr6:1000000-2005000`
- **Long-read WGS**: `wgs/long_read/` has `manifest.tsv` and `longreads.auxiliary_data.tsv`,
  per-center dirs (`BCM, BI, HA, JHU, UW`) by platform (`ont`, `pacbio`), joint calls
  (e.g. `BCM/ont/jointcall/GRCh38_noalt/ONT-BCM.chr21.g.vcf.bgz`), `haplotagged_bams/`, and
  `methylation/`. Each set exists for both GRCh38_noalt and T2Tv2.0.
- **Microarray**: `microarray/{hail.mt, plink, vcf/manifest.csv, idat/manifest.csv, aux}`.
  Read the MT with `hl.read_matrix_table(path, _load_refs=False)`.
- **RNA-seq**: `multiomics/rnaseq/` has `manifest.tsv`, `rnaseq_metadata.tsv`, `rsem/` (TPM),
  `rnaseqc2/`, `eqtl/`, and `sqtl/` (`{AFR,EUR,COMB}.cis_qtl.txt.gz`).
- **Proteomics (Olink)**: `multiomics/proteomics/` has `manifest.tsv`, `npx/` (parquet NPX),
  `pqtl/`, and `olink_report/`.
- **Reference genome**: `$HG38_REFERENCE_FASTA` (Broad public bucket, not requester-pays).
- `known_issues/` at the release root lists data problems. Check it when results look odd.

## Reading patterns

```bash
# VCF header and first records without downloading
gcloud storage cat --billing-project=$GOOGLE_PROJECT <vcf.bgz> | zcat | grep -v '^##' | head
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\n' "$AOU_CT_MOUNT/v9/.../exome/vcf/<file>.vcf.bgz" | head
# PLINK on a small callset (clinvar) is fine from the mount; copy big ones (acaf) to local disk first
plink2 --pfile "<prefix>" --freq --out chr1_freq
```
```python
import pandas as pd
anc = pd.read_csv(f"{os.environ['CDR_STORAGE_PATH']}/wgs/short_read/snpindel/aux/ancestry/ancestry_preds.tsv",
                  sep="\t", storage_options={"requester_pays": True})
```

## Performance and cost

- gcsfuse mounts are fine for headers, small files, and sequential reads. For PLINK/GWAS/PRS on
  acaf/exome files, many parallel readers, or random access, copy the files to local SSD or use a
  batch job (`aou-batch-jobs`). ACAF chr21 PLINK files alone are ~247 GiB, and localizing them
  in a dsub job took ~60 minutes.
- Check sizes with `du` before copying. Copy only the chromosomes you need.
- For Hail work, see the `aou-hail` skill.
- The tutorials live in `~/workspace/aou-tutorial-notebooks/03_Getting_Started_with_Genomic_Data/`
  and `04_Getting_Started_with_Multiomics_Data/`.
