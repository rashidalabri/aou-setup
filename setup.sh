#!/usr/bin/env bash
# Set up an All of Us (Verily Workbench) JupyterLab VM for analysis with Claude Code.
# Safe to re-run: every module is idempotent. See README.md.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

  (no options)        Run every module in order.
  --only a,b          Run only the named modules.
  --skip a,b          Run everything except the named modules.
  --create-buckets    Allow the buckets module to create missing workspace
                      buckets (workspace-bucket, temporary-workspace-bucket).
  --check             Only run the verification checks.
  --list              List modules and exit.
  -h, --help          Show this help.

Modules: buckets, env, python, workflows, claude, verify
EOF
}

module_files() { ls "$REPO_DIR"/modules/[0-9][0-9]-*.sh; }
module_name()  { basename "$1" .sh | sed 's/^[0-9]*-//'; }

ONLY="" SKIP=""
export AOU_CREATE_BUCKETS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)           ONLY="${2:?--only needs a value}"; shift ;;
    --skip)           SKIP="${2:?--skip needs a value}"; shift ;;
    --create-buckets) AOU_CREATE_BUCKETS=1 ;;
    --check)          ONLY="verify" ;;
    --list)           for f in $(module_files); do module_name "$f"; done; exit 0 ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

in_list() { [[ ",$2," == *",$1,"* ]]; }

have wb || die "The Workbench CLI (wb) was not found. Run this on a Verily Workbench app."

failed=()
for f in $(module_files); do
  name="$(module_name "$f")"
  [[ -n "$ONLY" ]] && ! in_list "$name" "$ONLY" && continue
  [[ -n "$SKIP" ]] && in_list "$name" "$SKIP" && continue
  section "$name"
  # Each module runs in its own shell so one failure doesn't stop the rest.
  if ! bash -c 'set -euo pipefail; source "$REPO_DIR/lib/common.sh"; load_aou_env; source "$1"' _ "$f"; then
    failed+=("$name")
  fi
done

echo
if [[ ${#failed[@]} -gt 0 ]]; then
  fail "Finished with problems in: ${failed[*]}"
  exit 1
fi
ok "Done. Open a new terminal (or run: source ~/.bashrc) to pick up the environment."
