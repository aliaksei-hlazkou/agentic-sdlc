import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';

type Outcome = 'completed' | 'failed';
type Operation = {
  result: Promise<Outcome>;
  settle: (outcome: Outcome) => void;
  feedback: Promise<void>;
  finishFeedback: () => void;
  observed: boolean;
};

// Only operation data survives reload. Never retain a Pi context in this registry.
const registryKey = Symbol.for('agentic-sdlc.orca-reload.pending.v2');
const processState = globalThis as typeof globalThis & {
  [registryKey]?: Map<string, Operation>;
};
const pending = processState[registryKey] ??= new Map<string, Operation>();

async function acknowledge(ctx: ExtensionContext, text: string): Promise<void> {
  await ctx.ui.select(text, ['OK']);
}

export default function orcaReload(pi: ExtensionAPI): void {
  let generation = 0;

  pi.on('session_shutdown', () => { generation++; });
  pi.on('session_start', (event, ctx) => {
    const reporterGeneration = ++generation;
    if (event.reason !== 'reload') return;
    const sessionId = ctx.sessionManager.getSessionId();
    const operation = pending.get(sessionId);
    if (!operation || operation.observed) return;
    operation.observed = true;

    // Do not await here: session_start runs before the reload promise resolves.
    void operation.result.then(async outcome => {
      if (generation !== reporterGeneration) return;
      await acknowledge(ctx, outcome === 'completed'
        ? 'Reload completed. Pi refreshed its runtime resources.'
        : 'Reload failed. Check the Pi diagnostics. Restart Pi if the session is unusable.');
    }).catch(() => {
      process.stderr.write('reload-orca: the result card could not be displayed. Check the session and restart Pi if needed.\n');
    }).finally(() => {
      if (pending.get(sessionId) === operation) pending.delete(sessionId);
      operation.finishFeedback();
    });
  });

  pi.registerCommand('reload-orca', {
    description: 'Reload Pi resources when idle; preserve the current model and conversation',
    handler: async (args, ctx) => {
      if (!ctx.hasUI) {
        process.stderr.write('reload-orca: a supported UI is required. Nothing was reloaded.\n');
        return;
      }
      if (ctx.mode !== 'rpc') {
        await acknowledge(ctx, "Use native /reload in Pi's terminal. /reload-orca is for RPC chat.");
        return;
      }
      if (args.trim()) {
        await acknowledge(ctx, 'Use /reload-orca without arguments. Nothing was reloaded.');
        return;
      }
      const sessionId = ctx.sessionManager.getSessionId();
      if (pending.has(sessionId)) {
        await acknowledge(ctx, 'A reload or its result card is still pending. Finish it before reloading again.');
        return;
      }
      if (!ctx.isIdle()) {
        await acknowledge(ctx, 'Wait for the current response or compaction to finish, then run /reload-orca again. Nothing was reloaded.');
        return;
      }

      const { promise, resolve } = Promise.withResolvers<Outcome>();
      const feedback = Promise.withResolvers<void>();
      const operation: Operation = {
        result: promise, settle: resolve,
        feedback: feedback.promise, finishFeedback: feedback.resolve,
        observed: false,
      };
      pending.set(sessionId, operation);
      let outcome: Outcome = 'failed';
      try {
        await ctx.reload();
        outcome = 'completed';
      } catch {
        // Do not expose raw exceptions or access a context invalidated by reload.
      }
      operation.settle(outcome);
      if (operation.observed) {
        // Orca cancels unanswered dialogs when the command returns. Wait using only plain state.
        await operation.feedback;
        return;
      }
      if (pending.get(sessionId) === operation) pending.delete(sessionId);
      process.stderr.write(outcome === 'completed'
        ? 'reload-orca: reload completed without a replacement reporter. Check the extension installation and restart Pi.\n'
        : 'reload-orca: reload failed before feedback was available. Restart Pi to recover.\n');
    },
  });
}
