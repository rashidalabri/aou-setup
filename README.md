# aou-setup

One command that gets an *All of Us* Researcher Workbench (Verily Workbench) JupyterLab app ready
for analysis, and teaches Claude Code how this environment works.

It reads everything workspace-specific (GCP project, CDR dataset, buckets, mounts) from the
Workbench CLI at run time, so the same repo works in any AoU workspace with no edits.

## Quick start

From a JupyterLab terminal in your workspace:

```bash
git clone https://github.com/rashidalabri/aou-setup.git ~/repos/aou-claude-setup
cd ~/repos/aou-claude-setup
./setup.sh
source ~/.bashrc
```

If the check at the end says `WORKSPACE_BUCKET` is missing, create the standard buckets and run it
again:

```bash
./setup.sh --create-buckets
```

Then start Claude Code (`claude`) from any directory.

## What it does

`setup.sh` runs these modules in order. Each one is safe to re-run.

| Module | What it does | Writes |
| --- | --- | --- |
| `buckets` | Checks for `workspace-bucket` and `temporary-workspace-bucket` (14-day auto-delete). Creates them only with `--create-buckets`. | Workspace resources |
| `env` | Resolves the project, CDR dataset and its index, buckets, CT data mount, and service account with `wb`. Values the platform already provides take precedence. | `~/.aou/env.sh`, `~/.aou/env.list`, a block in `~/.bashrc` |
| `python` | Fixes a known image problem: `import pandas_gbq` fails because `google-api-core` is too old. Upgrades it with `protobuf` pinned. Only acts if the import is broken. | Jupyter conda env |
| `workflows` | Installs an `aou_dsub` / `aou_dstat` helper and ready-to-use Cromwell and Nextflow configs (Google Batch, workspace VPC, private IPs, pet service account). | `~/.aou/aou_dsub.bash`, `~/.aou/cromwell.conf`, `~/.aou/nextflow.config` |
| `claude` | Installs Claude Code guidance: data-handling and cost rules, environment facts, and five skills. | A block in `~/.claude/CLAUDE.md`, `~/.claude/skills/aou-*` |
| `verify` | Read-only health checks: auth, variables, BigQuery dry run, imports, mounts, tools, Claude files. | Nothing |

Edits outside the marked blocks in `~/.bashrc` and `~/.claude/CLAUDE.md` are never touched.

### Claude Code skills

| Skill | Covers |
| --- | --- |
| `aou-workspace` | `wb` CLI, buckets, gcsfuse mounts, env variables, background notebook runs |
| `aou-cdr-bigquery` | OMOP/CDR map, Python/R/`bq` clients, tested SQL recipes (concepts, cohorts, surveys, labs, zip3/SES, death) |
| `aou-genomics-data` | Where every v9 genomic and multi-omic dataset lives and which format to choose |
| `aou-hail` | Hail init with requester pays, Dataproc sizing, GWAS recipe, subset/export helpers |
| `aou-batch-jobs` | dsub, Cromwell, and Nextflow on Google Batch with AoU's required settings |

`CLAUDE.md` tells Claude never to send participant data to external services, to mask counts of
1–20 (per the AoU dissemination policy), to dry-run BigQuery before large scans, and to ask before
launching paid jobs or creating resources.

## Usage

```bash
./setup.sh                       # everything
./setup.sh --check               # health checks only
./setup.sh --only env,claude     # selected modules
./setup.sh --skip python         # all but some
./setup.sh --list                # module names
```

Use the generated environment outside bash:

```r
readRenviron("~/.aou/env.list")        # R
```
```python
from pathlib import Path; import os    # Python
for line in Path("~/.aou/env.list").expanduser().read_text().splitlines():
    k, v = line.split("=", 1); os.environ.setdefault(k, v.strip('"'))
```

## When to re-run

- **After deleting and recreating the app.** Everything lives on the local disk, which isn't
  persistent. Keep this repo on GitHub, or in a workspace bucket, so it's easy to restore.
- **After adding or removing workspace resources, or switching CDR versions.** If
  `WORKSPACE_CDR` looks stale, delete `~/.aou-env` first.
- **After pulling updates to this repo.**

## Layout

```
setup.sh            entry point and module runner
lib/common.sh       logging, managed-block editing, template rendering
modules/NN-*.sh     one concern per module, run in numeric order
templates/          dsub helper, Cromwell and Nextflow config templates ({{VAR}} placeholders)
claude/CLAUDE.md    installed into ~/.claude/CLAUDE.md
claude/skills/      installed into ~/.claude/skills/
```

To add a module, drop `modules/NN-name.sh` into the folder. It runs in its own bash with
`lib/common.sh` and `~/.aou/env.sh` already loaded, and can call `ok`, `warn`, `die`, `render`, and
`upsert_block`.

## Requirements

A Verily Workbench JupyterLab app in an AoU workspace, with the CT data collection added. That
gives you `wb`, `gcloud`, `bq`, `jq`, and the conda `jupyter` env. Claude Code itself is installed
separately.
