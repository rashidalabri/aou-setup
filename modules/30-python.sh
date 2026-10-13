# Make sure the BigQuery client stack imports cleanly in the Jupyter Python env.
# Known issue (Oct 2026 image): google-cloud-bigquery 3.45 needs google-api-core >= 2.26,
# but 2.25.1 ships, so `import pandas_gbq` fails with
#   AttributeError: module 'google.api_core' has no attribute 'check_python_version'
# The fix upgrades google-api-core while pinning protobuf, so nothing else moves.
# pip then warns that dsub pins google-api-core<=2.25.1; that pin is conservative, and dsub
# (incl. the google-batch provider and --dry-run) works with the upgrade. verify re-checks it.

check_imports() { python -c 'import pandas_gbq, google.cloud.bigquery, db_dtypes' 2>&1; }

if err="$(check_imports)"; then
  ok "pandas_gbq / google-cloud-bigquery import cleanly"
  return 0
fi

warn "BigQuery client libraries fail to import: $(tail -n1 <<<"$err")"
protobuf_version="$(python -c 'import google.protobuf as p; print(p.__version__)')"
info "Upgrading google-api-core (protobuf pinned at $protobuf_version)..."
pip install --quiet --upgrade "google-api-core>=2.26" "protobuf==$protobuf_version"

if err="$(check_imports)"; then
  ok "Fixed: pandas_gbq / google-cloud-bigquery import cleanly"
  info "Restart any running Jupyter kernels to pick up the change."
else
  die "Still failing after upgrade: $(tail -n1 <<<"$err")"
fi
