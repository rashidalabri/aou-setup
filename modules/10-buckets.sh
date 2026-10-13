# Ensure the conventional workspace buckets exist.
#   workspace-bucket            persistent outputs ($WORKSPACE_BUCKET)
#   temporary-workspace-bucket  scratch, auto-deletes after 14 days ($WORKSPACE_TEMP_BUCKET)
# Creating cloud resources is opt-in: pass --create-buckets.

ensure_bucket() {
  local id="$1"; shift
  if wb resource resolve --id "$id" >/dev/null 2>&1; then
    ok "$id exists: $(wb resource resolve --id "$id")"
  elif [[ "$AOU_CREATE_BUCKETS" == 1 ]]; then
    wb resource create gcs-bucket --name="$id" --cloning=COPY_NOTHING "$@" >/dev/null
    ok "$id created: $(wb resource resolve --id "$id")"
  else
    warn "$id is missing. Re-run with --create-buckets to create it."
  fi
}

ensure_bucket workspace-bucket \
  --description="Primary workspace bucket for storing files"
ensure_bucket temporary-workspace-bucket \
  --auto-delete=14 \
  --description="Temporary storage; objects auto-delete after two weeks"
