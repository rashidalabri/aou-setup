# Read-only health checks. Exits non-zero if a required check fails.
# Nothing here bills more than a metadata request: BigQuery checks use --dry_run.

required_failed=0
check() {  # check <required|optional> <label> <command...>
  local level="$1" label="$2"; shift 2
  if "$@" >/dev/null 2>&1; then
    ok "$label"
  elif [[ "$level" == required ]]; then
    fail "$label"; required_failed=1
  else
    warn "$label"
  fi
}
is_set() { [[ -n "${!1:-}" ]]; }

info "Workbench"
check required "wb is logged in"                  bash -c '! wb auth status 2>&1 | grep -q "NO USER LOGGED IN"'
check required "GOOGLE_PROJECT"  is_set GOOGLE_PROJECT
check required "WORKSPACE_CDR"  is_set WORKSPACE_CDR
check optional "WORKSPACE_CDR_INDEX"  is_set WORKSPACE_CDR_INDEX
check optional "WORKSPACE_BUCKET"  is_set WORKSPACE_BUCKET
check optional "WORKSPACE_TEMP_BUCKET"  is_set WORKSPACE_TEMP_BUCKET

info "Data access"
check required "BigQuery: can query the CDR (dry run)" \
  bq query --quiet --use_legacy_sql=false --dry_run "SELECT person_id FROM \`${WORKSPACE_CDR:-missing}.person\` LIMIT 1"
check required "Python: pandas_gbq imports"       python -c 'import pandas_gbq'
check optional "Python: dsub Google Batch provider imports" python -c 'import dsub.providers.google_batch'
check optional "R: bigrquery is installed"        Rscript -e 'quit(status = !requireNamespace("bigrquery", quietly = TRUE))'
check optional "Controlled Tier bucket mounted"   test -d "${AOU_CT_MOUNT:-/nonexistent}"
if is_set CDR_STORAGE_PATH; then
  check optional "Genomic data bucket listable" \
    gcloud storage ls --billing-project="${GOOGLE_PROJECT:-}" "$CDR_STORAGE_PATH/"
fi
if is_set WORKSPACE_BUCKET; then
  check optional "Workspace bucket listable"      gcloud storage ls "$WORKSPACE_BUCKET/"
fi

info "Tools"
for tool in plink plink2 regenie bcftools samtools tabix dsub nextflow java; do
  check optional "$tool" have "$tool"
done
check optional "hail (Python)"                    python -c 'import hail'
check optional "Cromwell jar"                     test -f "${CROMWELL_JAR:-/nonexistent}"

info "Claude Code"
check optional "claude CLI on PATH"               have claude
check optional "~/.claude/CLAUDE.md has the AoU section" grep -q "BEGIN aou-claude-setup" "$HOME/.claude/CLAUDE.md"
for skill in "$REPO_DIR"/claude/skills/*/; do
  name="$(basename "$skill")"
  check optional "skill $name installed"          test -f "$HOME/.claude/skills/$name/SKILL.md"
done

[[ "$required_failed" == 0 ]] || die "Required checks failed (see ✗ above)."
