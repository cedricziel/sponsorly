#!/usr/bin/env bash
#
# Claude Code PostToolUse hook — formats the file that was just written/edited.
#   • Swift files                 -> swiftformat
#   • json/md/yml/yaml/web assets -> prettier via npx
#
# Non-blocking by design: any missing tool or formatter error is swallowed so a
# format hiccup never interrupts an edit. Wired up in .claude/settings.json.
set -euo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

case "$file" in
  *.swift)
    command -v swiftformat >/dev/null 2>&1 \
      && swiftformat "$file" >/dev/null 2>&1 || true
    ;;
  *.json|*.md|*.yml|*.yaml|*.js|*.ts|*.jsx|*.tsx|*.css|*.scss|*.html)
    command -v npx >/dev/null 2>&1 \
      && npx --yes prettier --write --ignore-unknown "$file" >/dev/null 2>&1 || true
    ;;
esac

exit 0
