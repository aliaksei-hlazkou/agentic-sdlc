# Orca reload

A small Pi extension for `/reload-orca` in RPC chat, including Orca. It uses Pi's public APIs. It does not modify Orca or Pi.

## Behavior

Run `/reload-orca` without arguments.

- Refuse reload while the parent agent is working or compacting. Do not wait or cancel work.
- Reload Pi's runtime resources through `ctx.reload()`.
- Keep the current session, conversation, model and thinking level. The extension does not change them.
- Show an OK card only after the reload operation completes. The replacement runtime displays the card.
- Keep the command pending until you acknowledge or dismiss the card. This prevents Orca from automatically cancelling it.
- Refuse another reload until the existing operation and result card finish.
- In Pi's terminal, direct the user to native `/reload` instead. Execute only in RPC mode.

Orca 1.4.244 ignores Pi notifications and custom message rows. Its supported question cards require an answer, so this extension uses one `OK` choice instead of a passive notification. No model request is needed. It adds no messages to the model's conversation.

`Reload completed` means that Pi's reload operation fulfilled. It does not certify that every third-party extension or other resource is healthy. Pi can record resource diagnostics without rejecting the reload operation.

## Safety boundary

**Finish background subagents before reloading.** Pi's parent-idle check does not establish that detached extension-owned work finished. This extension deliberately does not inspect pi-subagents internals.

Reload replaces extension-owned runtime state. It is not a process restart. Existing third-party extensions still control their own startup and shutdown behavior.

## Install in Pi

```bash
pi install git:github.com/aliaksei-hlazkou/agentic-sdlc@feat/orca-reload
```

The branch-qualified source installs this feature while its pull request is open. No manual folder setup, symlink or build is required.

Restart the Pi agent in Orca once to load the package, then run `/reload-orca`. Acknowledge or dismiss the result card to finish the command.

## Failure and recovery

The extension shows a fixed failure message when a valid replacement reporter is available. It does not display raw exceptions, credentials, configuration or session data.

If reload breaks or unloads this extension itself, a result card is not guaranteed. It writes a fixed diagnostic to stderr instead. Restore the extension installation if needed, then restart Pi. Orca may not display that stderr diagnostic in Chat.

If a result card cannot be displayed, the pending operation is cleared. Do not infer success from a missing card.

## Design

A session-keyed process-local registry holds only the completion and card-dismissal promises and result. It never stores a Pi context or UI object.

The replacement runtime observes the pending operation during `session_start` and returns from startup immediately. A detached promise continuation waits for the original reload call to settle, then uses the fresh context for feedback. A shutdown invalidates that reporter.

The old handler settles the reload outcome and waits for the fresh reporter's card to close. It uses only plain operation state, not stale Pi APIs. Orca cancels unanswered questions when a command-only turn ends, so the handler must not return before the card closes.

There are no production timers, watchers, files, subprocesses, model tools or extra dependencies.

## Tests

From the repository root:

```bash
node --test orca-reload/index.test.mjs
```

The tests need the installed Pi CLI on `PATH`. The RPC test uses `pi install` to register the package in a temporary agent directory. It uses a minimal environment and offline mode. It loads no ambient user/project extensions, credentials, MCP servers or context files. It runs two reloads, changes fixture extension code, adds skills and checks preserved session state without inference. The client simulates Orca's cancellation of unanswered questions at command completion. Tests verify that the command stays pending until the card is acknowledged or dismissed.

Verified on macOS with Node 26.4.0, Pi 1.4.0 and the Orca 1.4.244 RPC-dialog contract. The real Pi RPC path is tested. Orca's graphical UI still needs a manual smoke test after the initial restart.
