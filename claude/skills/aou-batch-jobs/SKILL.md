---
name: aou-batch-jobs
description: Run containerized batch jobs on Google Batch from the All of Us workbench with dsub, Cromwell (WDL), or Nextflow - preconfigured helpers, required network/service-account settings, Docker image mirror, monitoring, and logs. Use when work is too big for the notebook VM or must run in parallel per chromosome/sample.
---

# Batch jobs (dsub, Cromwell, Nextflow)

These launch billable VMs, so **confirm with the user before you submit**, and test on a small
input first (clinvar chr21 is the standard smoke test). All three tools need `$WORKSPACE_BUCKET`.
If it's unset, run `~/repos/aou-claude-setup/setup.sh --create-buckets` (ask first).

Required settings on AoU (the helpers below already apply them):
- Google Batch, region `us-central1`, VPC `global/networks/network` and subnetwork
  `regions/us-central1/subnetworks/subnetwork`, **private IPs only** (no external IP).
- Run as the pet service account (`$PET_SA_EMAIL` / `gcloud config get-value account`).
- Docker Hub isn't reachable directly. Prefix images with `$ARTIFACT_REGISTRY_DOCKER_REPO/`,
  e.g. `$ARTIFACT_REGISTRY_DOCKER_REPO/biocontainer/plink2:alpha2.3_jan2020` or
  `$ARTIFACT_REGISTRY_DOCKER_REPO/biocontainers/plink1.9:v1.90b6.6-181012-1-deb_cv1`.
- Genomic inputs are requester-pays. dsub passes `--user-project`. Nextflow sets
  `enableRequesterPaysBuckets`.

## dsub (`aou_dsub`, sourced from `~/.aou/aou_dsub.bash`)

```bash
JOB=$(aou_dsub \
  --name plink-chr21 \
  --image "$ARTIFACT_REGISTRY_DOCKER_REPO/biocontainer/plink2:alpha2.3_jan2020" \
  --machine-type n2-highmem-4 --boot-disk-size 20 --disk-size 50 \
  --input bed=gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/clinvar/plink_bed/clinvar.chr21.bed \
  --input bim=gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/clinvar/plink_bed/clinvar.chr21.bim \
  --input fam=gs://vwb-aou-datasets-controlled/v9/wgs/short_read/snpindel/clinvar/plink_bed/clinvar.chr21.fam \
  --input keep="$WORKSPACE_BUCKET/data/pid.txt" \
  --output-recursive out="$WORKSPACE_BUCKET/data/out" \
  --command 'plink2 --bfile "${bed%.bed}" --keep "$keep" --make-bed --out "$out/chr21_subset"')
aou_dstat --jobs "$JOB"          # add --full for details
```
- Inputs are localized under `/mnt/data/input/gs/<bucket>/<path>`. Localizing big files is slow
  (ACAF chr21 PLINK files ≈ 247 GiB ≈ 60 min), so size `--disk-size` to fit.
- Use `--tasks tasks.tsv` for one task per chromosome or sample.
- Logs go to `$WORKSPACE_BUCKET/dsub/logs/<job-name>/...`. A transient
  `401 Requester pays bucket access requires authentication` followed by a retry is harmless.
- `pip install --upgrade dsub` if a flag is missing. 0.5.x is known to work.

## Cromwell (run mode)

```bash
java -jar "$WOMTOOL_JAR" validate workflow.wdl
java -Dconfig.file="$HOME/.aou/cromwell.conf" -jar "$CROMWELL_JAR" run workflow.wdl -i inputs.json 2>&1 | tee cromwell.log
grep -E "workflow finished with status|Workflow actor for .* completed with status" cromwell.log
```
- Executions land in `$WORKSPACE_BUCKET/workflows/cromwell-executions/<workflow>/<id>/`.
- `runtime { docker: ...; memory: "8 GB"; cpu: 2; disks: "local-disk 200 HDD"; bootDiskSizeGb: 20 }`.
- Example: `~/workspace/aou-tutorial-notebooks/05_How_to_use_workflow_tools/02_How_to_use_cromwell/hello_world2.wdl`.
- For long or many workflows, the Workbench UI's **Workflows** tab runs Cromwell in server mode.

## Nextflow (25.10 installed)

```bash
nextflow -log run.log run main.nf -c "$HOME/.aou/nextflow.config" -profile gcb
grep -oE 'workDir: gs://[^ ]+' run.log | sort -u
```
- The work dir is `$WORKSPACE_BUCKET/workflows/nextflow-scratch`.
- Write DSL2 compatible with 25.10. Don't use the 26.04 strict syntax or typed records. Seqera
  Platform / Tower UI is unavailable (no outbound internet).
- When a `gs://` input is declared, Batch mounts its bucket under `/mnt/disks/<bucket>/` in the task.
  That's handy for reading companions like `.bim/.fam` without staging them. Avoid heavy random I/O
  on those mounts.
- CRAM slices can be streamed with samtools inside a task. Set
  `GCS_OAUTH_TOKEN=$(gcloud auth print-access-token)` and `GCS_REQUESTER_PAYS_PROJECT`. See
  `.../03_How_to_use_nextflow/cram_test_streaming.nf`.

## Choosing

dsub suits one command over N inputs. WDL/Cromwell suits multi-step pipelines that have existing
WDLs (Broad, GATK). Nextflow suits nf-core-style pipelines and streaming from mounted buckets.
Use Hail on Dataproc instead when the work is whole-cohort variant analysis on MT/VDS.
