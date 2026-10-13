# aou_dsub: dsub with the defaults required on the All of Us Researcher Workbench.
# Installed by aou-claude-setup. Any flag can be overridden by passing it again.
#
#   aou_dsub --name myjob \
#     --image "${ARTIFACT_REGISTRY_DOCKER_REPO}/biocontainer/plink2:alpha2.3_jan2020" \
#     --input fam=gs://... --output-recursive out=${WORKSPACE_BUCKET}/out \
#     --command 'plink2 ...'
#
# Check status:  aou_dstat --jobs <job-id> [--full]

_aou_dsub_user() {
  local email="${OWNER_EMAIL:-${WORKBENCH_USER_EMAIL:-$USER}}"
  echo "${email%%@*}" | tr '.' '-' | tr -d '\r'
}

aou_dsub() {
  : "${WORKSPACE_BUCKET:?WORKSPACE_BUCKET is not set; run aou-claude-setup with --create-buckets}"
  local region="${AOU_REGION:-us-central1}"
  dsub \
    --provider google-batch \
    --user-project "${GOOGLE_PROJECT}" \
    --project "${GOOGLE_PROJECT}" \
    --network "global/networks/network" \
    --subnetwork "regions/${region}/subnetworks/subnetwork" \
    --service-account "$(gcloud config get-value account 2>/dev/null)" \
    --use-private-address \
    --regions "${region}" \
    --user "$(_aou_dsub_user)" \
    --image "${ARTIFACT_REGISTRY_DOCKER_REPO}/ubuntu:latest" \
    --logging "${WORKSPACE_BUCKET}/dsub/logs/{job-name}/{user-id}/$(date +'%Y%m%d/%H%M%S')/{job-id}-{task-id}-{task-attempt}.log" \
    "$@"
}

aou_dstat() {
  dstat \
    --provider google-batch \
    --project "${GOOGLE_PROJECT}" \
    --location "${AOU_REGION:-us-central1}" \
    --users "$(_aou_dsub_user)" \
    --status '*' \
    "$@"
}
