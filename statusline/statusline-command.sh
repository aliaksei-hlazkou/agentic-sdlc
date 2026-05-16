#!/bin/bash
# Claude Code rich status line — configurable.
# Receives JSON on stdin from Claude Code.

# =====================================================================
#                           CONFIGURATION
# =====================================================================
# HOW TO CONFIGURE:
#
#   1) ORDER — space-separated list of segment names. The order here is
#      the order shown on screen. Add / remove / reorder entries freely.
#      Available names:
#        workspace  branch  cost  ctx  model  sid
#        todo  bg  agents  hooks  rl  mcp  mem
#
#   2) ENABLED_<name>=1   →  segment is shown
#      ENABLED_<name>=0   →  segment is hidden (still listed in ORDER, just skipped)
#
#   3) COLOR_<name>=<color-name>
#      Available colors: black red green yellow blue magenta cyan white
#                        dim bold
#
#   4) Save the file. Status line refreshes on the next Claude response.
#
# Defaults below: workspace, branch, cost, ctx, model, sid are ON.
# All others are OFF and listed at the end for easy enabling.
# =====================================================================

ORDER="workspace branch cost ctx model sid todo bg agents hooks rl mcp mem"

# enabled by default
ENABLED_workspace=1; COLOR_workspace=cyan
ENABLED_branch=1;    COLOR_branch=blue
ENABLED_cost=1;      COLOR_cost=green
ENABLED_ctx=1;       COLOR_ctx=yellow
ENABLED_model=1;     COLOR_model=dim
ENABLED_sid=1;       COLOR_sid=dim

# disabled by default — flip to 1 to enable
ENABLED_todo=0;      COLOR_todo=magenta
ENABLED_bg=0;        COLOR_bg=cyan
ENABLED_agents=0;    COLOR_agents=blue
ENABLED_hooks=0;     COLOR_hooks=dim
ENABLED_rl=0;        COLOR_rl=dim
ENABLED_mcp=0;       COLOR_mcp=dim
ENABLED_mem=0;       COLOR_mem=dim

# =====================================================================
#                    INTERNALS BELOW — usually no need to edit
# =====================================================================

input=$(cat)

# ---------- ANSI colors ----------
C_BLACK='\033[30m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_MAGENTA='\033[35m'
C_CYAN='\033[36m'
C_WHITE='\033[37m'
C_DIM='\033[2m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

SEP=" · "

resolve_color() {
  case "$1" in
    black)   printf '%b' "$C_BLACK"   ;;
    red)     printf '%b' "$C_RED"     ;;
    green)   printf '%b' "$C_GREEN"   ;;
    yellow)  printf '%b' "$C_YELLOW"  ;;
    blue)    printf '%b' "$C_BLUE"    ;;
    magenta) printf '%b' "$C_MAGENTA" ;;
    cyan)    printf '%b' "$C_CYAN"    ;;
    white)   printf '%b' "$C_WHITE"   ;;
    dim)     printf '%b' "$C_DIM"     ;;
    bold)    printf '%b' "$C_BOLD"    ;;
    *)       printf '%b' "$C_RESET"   ;;
  esac
}

emit() {
  local color text code
  color="$1"; text="$2"
  if [ -z "$text" ]; then return 0; fi
  code=$(resolve_color "$color")
  if [ -z "$OUT" ]; then
    OUT=$(printf '%b%s%b' "$code" "$text" "$C_RESET")
  else
    OUT=$(printf '%s%s%b%s%b' "$OUT" "$SEP" "$code" "$text" "$C_RESET")
  fi
}

TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
TRANSCRIPT_TAIL=""
load_transcript_tail() {
  if [ -n "$TRANSCRIPT_TAIL" ]; then return 0; fi
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    TRANSCRIPT_TAIL=$(tail -n 500 "$TRANSCRIPT_PATH" 2>/dev/null || true)
  fi
}

# ---------- Segment functions ----------

seg_workspace() {
  local pdir
  pdir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // ""' 2>/dev/null)
  [ -n "$pdir" ] && basename "$pdir" 2>/dev/null
}

seg_branch() {
  local cwd br dirty
  cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)
  [ -z "$cwd" ] && return 0
  git -C "$cwd" rev-parse --is-inside-work-tree --no-optional-locks >/dev/null 2>&1 || return 0
  br=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
       || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  [ -z "$br" ] && return 0
  dirty=""
  if ! git -C "$cwd" diff --quiet --no-optional-locks 2>/dev/null \
     || ! git -C "$cwd" diff --cached --quiet --no-optional-locks 2>/dev/null \
     || [ -n "$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
    dirty="✗"
  fi
  printf 'git:(%s)%s' "$br" "$dirty"
}

seg_cost() {
  local c
  c=$(echo "$input" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
  [ -z "$c" ] && return 0
  printf '$%.4f' "$c"
}

seg_ctx() {
  local total size pct k sk
  total=$(echo "$input" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)' 2>/dev/null)
  size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)
  pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
  [ -z "$total" ] || [ "$total" = "0" ] && return 0
  if [ "$total" -ge 1000 ]; then
    k=$(awk -v t="$total" 'BEGIN{printf "%.1fk", t/1000}')
  else
    k="$total"
  fi
  if [ "$size" -ge 1000000 ]; then
    sk=$(awk -v s="$size" 'BEGIN{printf "%.0fM", s/1000000}')
  else
    sk=$(awk -v s="$size" 'BEGIN{printf "%.0fk", s/1000}')
  fi
  printf '%s/%s (%s%%)' "$k" "$sk" "$pct"
}

seg_model() {
  local m
  m=$(echo "$input" | jq -r '.model.display_name // ""' 2>/dev/null)
  [ -z "$m" ] && return 0
  printf '%s' "$m"
}

seg_sid() {
  local s
  s=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
  [ -z "$s" ] && return 0
  printf 'sid:%s' "$(echo "$s" | cut -c1-8)"
}

seg_todo() {
  load_transcript_tail
  [ -z "$TRANSCRIPT_TAIL" ] && return 0
  local n
  n=$(echo "$TRANSCRIPT_TAIL" | jq -s '
    [ .[] | select(.type=="assistant") | .message.content[]?
      | select(type=="object" and .type=="tool_use" and .name=="TodoWrite")
      | .input.todos // [] ] | last // [] | length' 2>/dev/null)
  [ -z "$n" ] || [ "$n" = "0" ] && return 0
  printf 'todo:%s' "$n"
}

seg_bg() {
  load_transcript_tail
  [ -z "$TRANSCRIPT_TAIL" ] && return 0
  local n
  n=$(echo "$TRANSCRIPT_TAIL" | jq -s '
    [ .[] | select(.type=="assistant") | .message.content[]?
      | select(type=="object" and .type=="tool_use" and .name=="Bash")
      | select(.input.run_in_background==true) ] | length' 2>/dev/null)
  [ -z "$n" ] || [ "$n" = "0" ] && return 0
  printf 'bg:%s' "$n"
}

seg_agents() {
  load_transcript_tail
  [ -z "$TRANSCRIPT_TAIL" ] && return 0
  local n
  n=$(echo "$TRANSCRIPT_TAIL" | jq -s '
    [ .[] | select(.type=="assistant") | .message.content[]?
      | select(type=="object" and .type=="tool_use")
      | select(.name=="Agent" or .name=="Task") | .id ] as $ids |
    [ .[] | select(.type=="tool") | .content[]?
      | select(type=="object" and .type=="tool_result") | .tool_use_id ] as $done |
    [ $ids[] | select(. as $id | $done | index($id) == null) ] | length' 2>/dev/null)
  [ -z "$n" ] || [ "$n" = "0" ] && return 0
  printf 'agents:%s' "$n"
}

seg_hooks() {
  local g p n
  count_hooks() {
    local f="$1"
    if [ -f "$f" ]; then
      jq '[.hooks // {} | to_entries[] | .value | if type=="array" then .[] else . end | if type=="array" then length else 1 end] | add // 0' "$f" 2>/dev/null || echo 0
    else echo 0; fi
  }
  g=$(count_hooks "$HOME/.claude/settings.json")
  local pdir
  pdir=$(echo "$input" | jq -r '.workspace.project_dir // ""' 2>/dev/null)
  p=0
  [ -n "$pdir" ] && [ -f "${pdir}/.claude/settings.json" ] && p=$(count_hooks "${pdir}/.claude/settings.json")
  n=$(( g + p ))
  [ "$n" -le 0 ] && return 0
  printf 'hooks:%s' "$n"
}

seg_rl() {
  local h d s=""
  h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
  d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
  [ -z "$h" ] && [ -z "$d" ] && return 0
  s="rl:"
  [ -n "$h" ] && s="${s}5h=${h}%"
  [ -n "$h" ] && [ -n "$d" ] && s="${s}/"
  [ -n "$d" ] && s="${s}7d=${d}%"
  printf '%s' "$s"
}

seg_mcp() {
  local n
  n=$(jq '[.mcpServers // {} | keys[]] | length' "$HOME/.claude.json" 2>/dev/null || echo 0)
  [ -z "$n" ] || [ "$n" = "0" ] && return 0
  printf 'mcp:%s' "$n"
}

seg_mem() {
  local pdir slug d
  pdir=$(echo "$input" | jq -r '.workspace.project_dir // ""' 2>/dev/null)
  [ -z "$pdir" ] && return 0
  slug=$(printf '%s' "$pdir" | sed 's|/|-|g')
  d="$HOME/.claude/projects/${slug}/memory"
  [ ! -d "$d" ] && return 0
  local n
  n=$(find "$d" -maxdepth 1 -name "*.md" ! -name "MEMORY.md" 2>/dev/null | wc -l | tr -d ' ')
  [ -z "$n" ] || [ "$n" = "0" ] && return 0
  printf 'mem:%s' "$n"
}

# ---------- Dispatch ----------

OUT=""
for name in $ORDER; do
  enabled_var="ENABLED_${name}"
  color_var="COLOR_${name}"
  [ "${!enabled_var}" != "1" ] && continue
  text=$(seg_${name} 2>/dev/null)
  [ -n "$text" ] && emit "${!color_var}" "$text"
done

printf '%b\n' "$OUT"
