---
name: aou-workspace
description: Verily Workbench / All of Us workspace mechanics - the wb CLI, workspace resources, GCS buckets, gcsfuse mounts, environment variables, saving outputs, and running notebooks in the background. Use when locating or creating buckets/datasets, resolving resource paths, moving files, or diagnosing missing env vars.
---

# AoU workspace mechanics

## Workbench CLI (`wb`)

```bash
wb status                                  # current workspace + user
wb workspace describe --format=json        # .googleProjectId, etc.
wb resource list [--format=json]           # buckets, BQ datasets, referenced objects
wb resource resolve --id <resource-id>     # -> gs://bucket or project.dataset
wb resource describe --id <id> --format=JSON
wb resource mount [--name=<id>]            # (re)mount buckets under ~/workspace
wb auth status
```

Resource types: `GCS_BUCKET`, `BQ_DATASET`, `GCS_OBJECT` (referenced folder). CDR datasets match
`C<year>Q<q>R<release>` (e.g. `C2025Q4R6` = CT v9). A typical tutorial workspace also references
`prep_<CDR>`, `C_V9_R3_aou_biospecimen`, and `C_V9_R6_offcycle_nlp` datasets, the tutorial bucket
`aou-tutorial-notebooks`, and the CT data bucket `vwb-aou-datasets-controlled-v9`.

## Buckets

| id | purpose |
| --- | --- |
| `workspace-bucket` → `$WORKSPACE_BUCKET` | persistent outputs, shared with collaborators |
| `temporary-workspace-bucket` → `$WORKSPACE_TEMP_BUCKET` | scratch; objects auto-delete after 14 days |
| `rw-migration-*` | carried over from Researcher Workbench 1.0 (used as `WORKSPACE_BUCKET` when no workspace-bucket exists) |

Creating them is a cloud-resource change, so ask the user first. Then run
`~/repos/aou-claude-setup/setup.sh --create-buckets` (it also refreshes the env vars), or:

```bash
wb resource create gcs-bucket --name=workspace-bucket --cloning=COPY_NOTHING \
  --description="Primary workspace bucket for storing files"
wb resource create gcs-bucket --name=temporary-workspace-bucket --cloning=COPY_NOTHING \
  --auto-delete=14 --description="Temporary storage"
```

`--cloning=COPY_NOTHING` stops the bucket from copying when the workspace is duplicated. Buckets
created in the UI default to `COPY_RESOURCE`.

## Copying files

```bash
gcloud storage cp results.tsv "$WORKSPACE_BUCKET/data/"
gcloud storage ls -l "$WORKSPACE_BUCKET/data/"
gcloud storage ls --billing-project="$GOOGLE_PROJECT" "$CDR_STORAGE_PATH/"   # requester-pays
```

In Python, `pd.read_csv("gs://...")` works. Add `storage_options={"requester_pays": True}` for AoU
data buckets.

## Mounts

- General apps mount at `/home/jupyter/workspace/`. Dataproc apps mount at `/home/dataproc/workspace/`.
- Folder names can contain spaces, e.g.
  `~/workspace/Data from All of Us Controlled Tier /vwb-aou-datasets-controlled-v9/v9/...`
  (note the trailing space before `/`). Always quote these paths. `$AOU_CT_MOUNT` holds the
  resolved path.
- Mounts are good for browsing, reading small files, and sequential streaming. They're bad for
  random-access or high-throughput I/O. The app's local disk is not persistent, so save anything
  you want to keep to a bucket or mount.
- "No such file or directory" on a mount usually means it isn't mounted (`wb resource mount`) or
  the path isn't quoted.

## Environment variables

`~/.bashrc` sources `~/load-env.sh`. That script caches the platform values (`WORKSPACE_CDR`,
`CDR_STORAGE_PATH`, `WGS_*`, `MICROARRAY_*`, `HG38_REFERENCE_*`, `ARTIFACT_REGISTRY_DOCKER_REPO`) in
`~/.aou-env`. Then `~/.bashrc` sources `~/.aou/env.sh`, which aou-claude-setup generates from
`wb resource list` (buckets, CDR index, mounts, pet service account). If either looks stale after
a CDR or resource change, delete `~/.aou-env` and re-run `setup.sh --only env`.

The tutorials use `%run Setting_Env_Variables.py` and `Setting_Env_Variables_p2.py`, which append
exports to `~/.bashrc`. Prefer `~/.aou/env.list` in new code.

## Running a notebook unattended

```bash
nohup jupyter nbconvert --to notebook --execute --ExecutePreprocessor.timeout=-1 \
  --output "run_$(date +%Y%m%d_%H%M%S).ipynb" analysis.ipynb > run.log 2>&1 &
```

Use `--ExecutePreprocessor.kernel_name=ir` for R notebooks. Check on it with `top`, or with
`yarn application -list` on Dataproc.

## Costs

Stopping an app only pauses it, and disks still bill. Deleting an app stops the charges but loses
local disk. Workbench shows no live cost estimate, so check the GCP billing report.
