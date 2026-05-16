#!/usr/bin/env bash
# Claude Code statusline installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/statusline/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/statusline"
SCRIPT_URL="${REPO_RAW}/statusline-command.sh"

CLAUDE_DIR="${HOME}/.claude"
SCRIPT_DEST="${CLAUDE_DIR}/statusline-command.sh"
SETTINGS="${CLAUDE_DIR}/settings.json"

c_bold=$'\033[1m'
c_green=$'\033[32m'
c_red=$'\033[31m'
c_yellow=$'\033[33m'
c_dim=$'\033[2m'
c_reset=$'\033[0m'

info()  { printf '%s%s%s\n' "$c_bold" "$*" "$c_reset"; }
ok()    { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn()  { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
fail()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

detect_os() {
  case "$(uname -s)" in
    Darwin*) echo "macos" ;;
    Linux*)  echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

install_hint() {
  local tool="$1" os="$2"
  case "$os" in
    macos)   echo "brew install ${tool}" ;;
    linux)   echo "sudo apt install ${tool}   (or: dnf install ${tool} / pacman -S ${tool})" ;;
    windows) echo "winget install jqlang.${tool}   (or use chocolatey: choco install ${tool})" ;;
    *)       echo "install '${tool}' via your package manager" ;;
  esac
}

OS=$(detect_os)
info "Claude Code statusline installer (${OS})"

# ---------- Dependency checks ----------
for bin in bash curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    warn "missing dependency: ${bin}"
    fail "install it first → $(install_hint "$bin" "$OS")"
  fi
done
ok "dependencies present (bash, curl, jq)"

# ---------- Download script ----------
mkdir -p "$CLAUDE_DIR"
info "downloading statusline script…"
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_DEST" || fail "download failed from ${SCRIPT_URL}"
chmod +x "$SCRIPT_DEST"
ok "installed → ${SCRIPT_DEST}"

# ---------- Patch settings.json ----------
NEW_CMD="bash ${SCRIPT_DEST}"

if [ ! -f "$SETTINGS" ]; then
  info "creating ${SETTINGS}"
  printf '{\n  "statusLine": {\n    "type": "command",\n    "command": "%s"\n  }\n}\n' "$NEW_CMD" > "$SETTINGS"
  ok "settings.json created with statusLine"
else
  ts=$(date +%Y%m%d-%H%M%S)
  cp "$SETTINGS" "${SETTINGS}.bak.${ts}"
  ok "backed up existing settings → ${SETTINGS}.bak.${ts}"
  tmp=$(mktemp)
  jq --arg cmd "$NEW_CMD" '.statusLine = {type:"command", command:$cmd}' "$SETTINGS" > "$tmp" \
    || fail "jq failed to patch settings.json (existing file may be invalid JSON)"
  mv "$tmp" "$SETTINGS"
  ok "settings.json updated"
fi

printf '\n%sDone.%s Restart Claude Code (or run %s/statusline%s) to apply.\n' \
  "$c_bold" "$c_reset" "$c_dim" "$c_reset"
