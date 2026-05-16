# Caveman Skill for Claude Code

A productivity skill that flips Claude Code into **caveman mode** — terse, grunting, no fluff. Useful when you want fast minimal responses instead of polished prose.

Activate by saying *"caveman mode"* (or *"caveman on"*) in any Claude Code session after the skill is installed. Deactivate with *"normal mode"* or *"stop caveman"*.

## What gets installed

A single file: `SKILL.md` placed at one of:

- **User scope (default):** `~/.claude/skills/productivity/caveman/SKILL.md` — active in every Claude Code session you start
- **Project scope:** `<project>/.claude/skills/productivity/caveman/SKILL.md` — only active when Claude Code runs inside that project

Claude Code auto-discovers skills from those paths; no `settings.json` edits are needed.

## Install (one-liner)

### macOS / Linux / WSL / Git Bash

User-level (default):

```bash
curl -fsSL https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.sh | bash
```

Project-level (installs into current directory):

```bash
curl -fsSL https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.sh | bash -s -- --project
```

Project-level at a specific path:

```bash
curl -fsSL https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.sh | bash -s -- --project /path/to/repo
```

Run with **no flags** in an interactive terminal and the installer will prompt for scope.

### Windows PowerShell

User-level (default — interactive prompt):

```powershell
iwr -useb https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.ps1 | iex
```

Non-interactive with explicit scope:

```powershell
$s = iwr -useb https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.ps1
& ([scriptblock]::Create($s)) -Scope user
# or
& ([scriptblock]::Create($s)) -Scope project -ProjectPath C:\path\to\repo
```

## Manual install

```bash
mkdir -p ~/.claude/skills/productivity/caveman
curl -fsSL https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/SKILL.md \
  -o ~/.claude/skills/productivity/caveman/SKILL.md
```

Or for project scope, replace `~` with the project path.

## Uninstall

```bash
# user scope
rm -rf ~/.claude/skills/productivity/caveman

# project scope
rm -rf ./.claude/skills/productivity/caveman
```

## Notes

- If a `SKILL.md` already exists at the target, the installer backs it up as `SKILL.md.bak.<timestamp>` before overwriting.
- Skills are picked up at session start, so restart Claude Code (or open a new session) after install.
- Windows native PowerShell is supported via `install.ps1`. WSL and Git Bash users should use `install.sh` instead.
