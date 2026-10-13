# Write ready-to-use configs for the batch workflow tools, all running on Google Batch
# inside the workspace VPC with the pet service account:
#   ~/.aou/aou_dsub.bash      aou_dsub function (dsub with AoU defaults); sourced from ~/.bashrc
#   ~/.aou/cromwell.conf      Cromwell run-mode config
#   ~/.aou/nextflow.config    Nextflow config with a "gcb" profile

TEMPLATES="$REPO_DIR/templates"

cp "$TEMPLATES/aou_dsub.bash" "$AOU_HOME/aou_dsub.bash"
ok "dsub helper: $AOU_HOME/aou_dsub.bash (function: aou_dsub)"

if [[ -z "${WORKSPACE_BUCKET:-}" ]]; then
  warn "WORKSPACE_BUCKET is not set; skipping Cromwell and Nextflow configs (they need a bucket for work dirs)."
  info "Run ./setup.sh --create-buckets, then re-run."
  return 0
fi

render "$TEMPLATES/cromwell.conf" "$AOU_HOME/cromwell.conf" \
  GOOGLE_PROJECT WORKSPACE_BUCKET PET_SA_EMAIL AOU_REGION
ok "Cromwell config: $AOU_HOME/cromwell.conf"

render "$TEMPLATES/nextflow.config" "$AOU_HOME/nextflow.config" \
  GOOGLE_PROJECT WORKSPACE_BUCKET PET_SA_EMAIL AOU_REGION
ok "Nextflow config: $AOU_HOME/nextflow.config (profile: gcb)"
