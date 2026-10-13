# Shared helpers for setup.sh and modules/. Sourced, never executed.

AOU_HOME="${AOU_HOME:-$HOME/.aou}"
AOU_ENV_FILE="$AOU_HOME/env.sh"
AOU_ENV_LIST="$AOU_HOME/env.list"
AOU_REGION="${AOU_REGION:-us-central1}"
AOU_DEFAULT_DOCKER_REPO="us-central1-docker.pkg.dev/all-of-us-rw-prod/aou-rw-gar-remote-repo-docker-prod"

if [[ -t 1 ]]; then
  _c_red=$'\e[31m' _c_grn=$'\e[32m' _c_ylw=$'\e[33m' _c_bld=$'\e[1m' _c_off=$'\e[0m'
else
  _c_red='' _c_grn='' _c_ylw='' _c_bld='' _c_off=''
fi

section() { printf '\n%s== %s ==%s\n' "$_c_bld" "$*" "$_c_off"; }
info()    { printf '   %s\n' "$*"; }
ok()      { printf ' %s✓%s %s\n' "$_c_grn" "$_c_off" "$*"; }
warn()    { printf ' %s!%s %s\n' "$_c_ylw" "$_c_off" "$*" >&2; }
fail()    { printf ' %s✗%s %s\n' "$_c_red" "$_c_off" "$*" >&2; }
die()     { fail "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Load the generated environment file if it exists (quietly).
load_aou_env() {
  # shellcheck disable=SC1090
  [[ -f "$AOU_ENV_FILE" ]] && source "$AOU_ENV_FILE"
  return 0
}

# Replace (or append) a marker-delimited block in a file, leaving the rest untouched.
#   upsert_block <file> <begin-line> <end-line> <content>
upsert_block() {
  local file="$1" begin="$2" end="$3" content="$4"
  local tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    !skip
  ' "$file" > "$tmp"
  # Drop trailing blank lines so repeated runs don't accumulate whitespace.
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
  { [[ -s "$tmp" ]] && printf '\n'; printf '%s\n%s\n%s\n' "$begin" "$content" "$end"; } >> "$tmp"
  cat "$tmp" > "$file"  # preserves the original file's permissions
  rm -f "$tmp"
}

# Render a template, replacing {{VAR}} placeholders with values of the named variables.
#   render <template> <output> VAR [VAR...]
render() {
  local tmpl="$1" out="$2"; shift 2
  local text var
  text="$(<"$tmpl")"
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || die "render: \$$var is empty (needed by $(basename "$tmpl"))"
    text="${text//\{\{$var\}\}/${!var}}"
  done
  mkdir -p "$(dirname "$out")"
  printf '%s\n' "$text" > "$out"
}
