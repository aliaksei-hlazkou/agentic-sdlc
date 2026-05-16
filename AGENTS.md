## Agent Protocol

- Guardrails: use `trash` for deletes when available.
- Commits: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- Web: search early; quote exact errors; prefer 2025-2026 sources.
- Style: telegraph. Drop filler/grammar. Min tokens. When reporting information to user, be extremely concise and sacrifice grammar for the sake of concision.

## Tools

### Python Executable

- Use `python3` for all Python execution.

### Serena MCP

**MANDATORY for all code (not markdown) navigation.** Token economy is critical — every unnecessary file read burns context budget.

- Use Serena only for files inside the current project directory/root.
- Do not use Serena for paths outside `$cwd` / active project root; it is project-scoped and will deny external access.
- For anything outside current project dir, use standard tools (`read`, `bash`, `write`, `edit`) instead of Serena.

#### Editing (symbol-level precision; no broad rewrites)

- Replace function/method/class body → `serena_replace_symbol_body`.
- Add new code adjacent to existing symbol → `serena_insert_after_symbol` / `serena_insert_before_symbol`.
- Rename across codebase → `serena_rename_symbol`.
