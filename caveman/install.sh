#!/usr/bin/env bash
# Caveman skill installer for Claude Code
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.sh | bash
#   curl -fsSL ... | bash -s -- --user
#   curl -fsSL ... | bash -s -- --project [/path/to/project]
#
# Flags:
#   --user                Install to $HOME/.claude/skills (default)
#   --project [PATH]      Install to <PATH>/.claude/skills (defaults to current dir)
#   --help                Show help

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman"
SKILL_URL="${REPO_RAW}/SKILL.md"
REL_PATH=".claude/skills/productivity/caveman/SKILL.md"

c_bold=$'\033[1m'; c_green=$'\033[32m'; c_red=$'\033[31m'
c_yellow=$'\033[33m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
info()  { printf '%s%s%s\n' "$c_bold" "$*" "$c_reset"; }
ok()    { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn()  { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
fail()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

usage() {
  sed -n '2,11p' "$0" 2>/dev/null || cat <<EOF
Caveman skill installer.
  --user                Install to \$HOME/.claude/skills (default)
  --project [PATH]      Install to <PATH>/.claude/skills (defaults to current dir)
  --help                Show help
EOF
  exit 0
}

SCOPE=""
PROJECT_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --user)    SCOPE="user"; shift ;;
    --project) SCOPE="project"; shift
               if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then PROJECT_PATH="$1"; shift; fi ;;
    --help|-h) usage ;;
    *) fail "unknown flag: $1 (try --help)" ;;
  esac
done

# Interactive prompt if no flag and a TTY is available
if [ -z "$SCOPE" ]; then
  if [ -t 1 ] && [ -r /dev/tty ]; then
    printf 'Install scope?\n  1) user    (~/.claude/skills) — default\n  2) project (./.claude/skills)\nChoice [1]: ' > /dev/tty
    read -r choice < /dev/tty || choice=""
    case "${choice:-1}" in
      1|u|user)    SCOPE="user" ;;
      2|p|project) SCOPE="project" ;;
      *) fail "invalid choice: $choice" ;;
    esac
  else
    SCOPE="user"
  fi
fi

# Resolve target dir
case "$SCOPE" in
  user)    BASE="$HOME" ;;
  project) BASE="${PROJECT_PATH:-$PWD}" ;;
  *) fail "internal error: bad scope '$SCOPE'" ;;
esac

DEST="${BASE}/${REL_PATH}"
DEST_DIR=$(dirname "$DEST")

# Sanity checks
command -v curl >/dev/null 2>&1 || fail "curl is required"
[ -d "$BASE" ] || fail "target base does not exist: $BASE"

info "Installing caveman skill (scope: ${SCOPE})"
info "  target: ${DEST}"

if [ -f "$DEST" ]; then
  ts=$(date +%Y%m%d-%H%M%S)
  cp "$DEST" "${DEST}.bak.${ts}"
  ok "backed up existing SKILL.md → ${DEST}.bak.${ts}"
fi

mkdir -p "$DEST_DIR"
curl -fsSL "$SKILL_URL" -o "$DEST" || fail "download failed from ${SKILL_URL}"
ok "installed → ${DEST}"

printf '\n%sDone.%s Restart Claude Code (or start a new session) to activate.\n' \
  "$c_bold" "$c_reset"
printf 'To trigger: say %s"caveman mode"%s in any session.\n' "$c_dim" "$c_reset"
