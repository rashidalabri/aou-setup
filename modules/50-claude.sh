# Install Claude Code guidance at the user level so it applies wherever `claude` starts:
#   ~/.claude/CLAUDE.md          AoU section inside a managed block (your own text is kept)
#   ~/.claude/skills/aou-*       one directory per skill (replaced on every run)

CLAUDE_DIR="$HOME/.claude"
SRC="$REPO_DIR/claude"

upsert_block "$CLAUDE_DIR/CLAUDE.md" \
  "<!-- BEGIN aou-claude-setup (managed: edits inside this block are overwritten) -->" \
  "<!-- END aou-claude-setup -->" \
  "$(<"$SRC/CLAUDE.md")"
ok "CLAUDE.md -> $CLAUDE_DIR/CLAUDE.md"

mkdir -p "$CLAUDE_DIR/skills"
for skill in "$SRC"/skills/*/; do
  name="$(basename "$skill")"
  rm -rf "${CLAUDE_DIR:?}/skills/$name"
  cp -r "$skill" "$CLAUDE_DIR/skills/$name"
  ok "skill: $name"
done

have claude || warn "The claude CLI is not on PATH. Install Claude Code, then start it with: claude"
