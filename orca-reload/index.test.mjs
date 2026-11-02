import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import orcaReload from './index.ts';

const tick = () => new Promise(resolve => setImmediate(resolve));
let nextSession = 0;

function runtime({ sessionId = `test-${++nextSession}`, idle = true, hasUI = true, mode = 'rpc', choice } = {}) {
  let active = true;
  let reload = () => { throw new Error('Unexpected reload'); };
  const handlers = new Map();
  const dialogs = [];
  const commands = new Map();
  const check = () => assert.ok(active, 'A stale context was used');
  const ui = { select: async (title, options) => {
    check();
    dialogs.push({ title, options });
    return choice ? choice(title) : 'OK';
  } };
  const ctx = {
    get ui() { check(); return ui; },
    get hasUI() { check(); return hasUI; },
    get mode() { check(); return mode; },
    get sessionManager() { check(); return { getSessionId: () => sessionId }; },
    isIdle() { check(); return idle; },
    reload() { check(); return reload(); },
  };
  orcaReload({
    on: (event, handler) => handlers.set(event, handler),
    registerCommand: (name, command) => commands.set(name, command),
  });
  return {
    sessionId, dialogs,
    command: args => commands.get('reload-orca').handler(args, ctx),
    onReload: handler => { reload = handler; },
    start: () => handlers.get('session_start')({ reason: 'reload' }, ctx),
    retire: () => { handlers.get('session_shutdown')(); active = false; },
  };
}

test('busy sessions refuse reload without waiting or cancelling', async () => {
  const current = runtime({ idle: false });
  await current.command('');
  assert.match(current.dialogs[0].title, /response or compaction/);
  assert.deepEqual(current.dialogs[0].options, ['OK']);
});

test('the terminal uses native reload instead of the RPC-only command', async () => {
  const current = runtime({ mode: 'tui' });
  await current.command('');
  assert.match(current.dialogs[0].title, /Use native \/reload/);
});

test('arguments are rejected', async () => {
  const current = runtime();
  await current.command('force');
  assert.match(current.dialogs[0].title, /without arguments/);
});

test('a non-UI process refuses without reloading', async t => {
  const diagnostics = [];
  t.mock.method(process.stderr, 'write', text => { diagnostics.push(text); return true; });
  await runtime({ hasUI: false }).command('');
  assert.match(diagnostics.join(''), /Nothing was reloaded/);
});

test('success waits for full reload and uses only the replacement context', async () => {
  const previous = runtime();
  const gate = Promise.withResolvers();
  let replacement;
  previous.onReload(async () => {
    previous.retire();
    replacement = runtime({ sessionId: previous.sessionId });
    replacement.start();
    await gate.promise;
  });
  const command = previous.command('');
  await tick();
  assert.equal(replacement.dialogs.length, 0, 'startup is not reload completion');
  gate.resolve();
  await command;
  await tick();
  assert.match(replacement.dialogs[0].title, /^Reload completed/);
  assert.equal(previous.dialogs.length, 0);
});

test('reload failure reports failure through the fresh context, without exception text', async () => {
  const previous = runtime();
  let replacement;
  previous.onReload(async () => {
    previous.retire();
    replacement = runtime({ sessionId: previous.sessionId });
    replacement.start();
    throw new Error('PRIVATE_EXCEPTION_SENTINEL');
  });
  await previous.command('');
  await tick();
  assert.match(replacement.dialogs[0].title, /^Reload failed/);
  assert.doesNotMatch(replacement.dialogs[0].title, /PRIVATE_EXCEPTION_SENTINEL|completed/);
});

test('a replacement that shuts down before completion does not use its stale context', async () => {
  const previous = runtime();
  let replacement;
  previous.onReload(async () => {
    previous.retire();
    replacement = runtime({ sessionId: previous.sessionId });
    replacement.start();
    replacement.retire();
  });
  await previous.command('');
  await tick();
  assert.equal(replacement.dialogs.length, 0);
});

test('missing replacement feedback is not fabricated and does not block a later reload', async t => {
  const diagnostics = [];
  t.mock.method(process.stderr, 'write', text => { diagnostics.push(text); return true; });
  const current = runtime();
  let calls = 0;
  current.onReload(async () => { calls++; throw new Error('PRIVATE_EXCEPTION_SENTINEL'); });
  await current.command('');
  await current.command('');
  assert.equal(calls, 2);
  assert.equal(current.dialogs.length, 0);
  assert.match(diagnostics.join(''), /failed before feedback/);
  assert.doesNotMatch(diagnostics.join(''), /PRIVATE_EXCEPTION_SENTINEL|Reload completed/);
});

test('unloading the extension does not fabricate a result card', async t => {
  const diagnostics = [];
  t.mock.method(process.stderr, 'write', text => { diagnostics.push(text); return true; });
  const previous = runtime();
  previous.onReload(async () => previous.retire());
  await previous.command('');
  assert.equal(previous.dialogs.length, 0);
  assert.match(diagnostics.join(''), /without a replacement reporter/);
});

test('a failed result dialog does not expose its exception or retain the operation', async t => {
  const diagnostics = [];
  t.mock.method(process.stderr, 'write', text => { diagnostics.push(text); return true; });
  const previous = runtime();
  let replacement;
  previous.onReload(async () => {
    previous.retire();
    replacement = runtime({ sessionId: previous.sessionId,
      choice: () => { throw new Error('PRIVATE_EXCEPTION_SENTINEL'); } });
    replacement.start();
  });
  await previous.command('');
  await tick();
  assert.match(diagnostics.join(''), /result card could not be displayed/);
  assert.doesNotMatch(diagnostics.join(''), /PRIVATE_EXCEPTION_SENTINEL/);
  let finalRuntime;
  replacement.onReload(async () => {
    replacement.retire();
    finalRuntime = runtime({ sessionId: previous.sessionId });
    finalRuntime.start();
  });
  await replacement.command('');
  await tick();
  assert.match(finalRuntime.dialogs[0].title, /^Reload completed/);
});

test('a pending result prevents another reload until acknowledgment, then permits retry', async () => {
  const acknowledgment = Promise.withResolvers();
  const previous = runtime();
  let replacement;
  previous.onReload(async () => {
    previous.retire();
    replacement = runtime({ sessionId: previous.sessionId,
      choice: title => title.startsWith('Reload completed') ? acknowledgment.promise : 'OK' });
    replacement.start();
  });
  let commandReturned = false;
  const command = previous.command('').then(() => { commandReturned = true; });
  await tick();
  assert.equal(commandReturned, false, 'the command must not finish before the result card');
  await replacement.command('');
  assert.match(replacement.dialogs.at(-1).title, /still pending/);
  acknowledgment.resolve('OK');
  await command;
  await tick();
  let finalRuntime;
  replacement.onReload(async () => {
    replacement.retire();
    finalRuntime = runtime({ sessionId: previous.sessionId });
    finalRuntime.start();
  });
  await replacement.command('');
  await tick();
  assert.match(finalRuntime.dialogs[0].title, /^Reload completed/);
});

function rpcProcess(args, options) {
  const child = spawn('pi', args, { ...options, stdio: ['pipe', 'pipe', 'pipe'] });
  const requests = new Map();
  const events = [];
  const openDialogs = new Set();
  const autoCancelledDialogs = [];
  const eventWaiters = new Set();
  let sequence = 0;
  let buffer = '';
  let stderr = '';
  let processError;
  child.stderr.on('data', chunk => { stderr += chunk; });
  child.stdout.on('data', chunk => {
    buffer += chunk.toString('utf8');
    while (buffer.includes('\n')) {
      const index = buffer.indexOf('\n');
      const line = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      if (!line.trim()) continue;
      let record;
      try { record = JSON.parse(line); } catch { continue; }
      if (record.type === 'response' && requests.has(record.id)) {
        const pending = requests.get(record.id);
        requests.delete(record.id);
        clearTimeout(pending.timer);
        // Orca closes outstanding questions when a command-only turn settles.
        if (record.command === 'prompt' && record.data?.disposition === 'handled') {
          for (const id of openDialogs) {
            autoCancelledDialogs.push(id);
            send({ type: 'extension_ui_response', id, cancelled: true });
          }
        }
        record.success ? pending.resolve(record.data) : pending.reject(new Error(record.error));
      } else {
        if (record.type === 'extension_ui_request' && record.method === 'select') openDialogs.add(record.id);
        events.push(record);
        for (const waiter of eventWaiters) {
          if (waiter.matches(record)) {
            clearTimeout(waiter.timer);
            eventWaiters.delete(waiter);
            waiter.resolve(record);
          }
        }
      }
    }
  });
  child.on('error', error => { processError = error; });
  const send = record => {
    if (record.type === 'extension_ui_response') openDialogs.delete(record.id);
    child.stdin.write(`${JSON.stringify(record)}\n`);
  };
  const request = (type, data = {}) => new Promise((resolve, reject) => {
    if (processError) return reject(processError);
    const id = `test-${++sequence}`;
    const timer = setTimeout(() => {
      requests.delete(id);
      reject(new Error(`Pi RPC ${type} timed out. ${stderr}`));
    }, 20_000);
    requests.set(id, { resolve, reject, timer });
    send({ type, id, ...data });
  });
  const waitFor = matches => new Promise((resolve, reject) => {
    const existing = events.find(matches);
    if (existing) return resolve(existing);
    const waiter = { matches, resolve, timer: setTimeout(() => {
      eventWaiters.delete(waiter);
      reject(new Error(`Pi RPC event timed out. ${stderr}`));
    }, 20_000) };
    eventWaiters.add(waiter);
  });
  return { child, events, autoCancelledDialogs, request, waitFor, send,
    async close() {
      for (const pending of requests.values()) clearTimeout(pending.timer);
      for (const waiter of eventWaiters) clearTimeout(waiter.timer);
      child.stdin.end();
      if (child.exitCode !== null) return;
      await new Promise(resolve => {
        const timer = setTimeout(() => { child.kill('SIGKILL'); resolve(); }, 5_000);
        child.once('exit', () => { clearTimeout(timer); resolve(); });
      });
    },
  };
}

test('isolated real Pi RPC reload through pi install preserves session state', { timeout: 90_000 }, async t => {
  const root = await mkdtemp(path.join(tmpdir(), 'orca-reload-test-'));
  const skills = path.join(root, 'skills');
  const agentDir = path.join(root, 'agent');
  await mkdir(skills);
  const env = {
    PATH: process.env.PATH, HOME: root, TMPDIR: root,
    PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: '1',
  };
  const installed = spawnSync('pi', ['install', fileURLToPath(new URL('..', import.meta.url))], {
    cwd: root, env, encoding: 'utf8', timeout: 20_000,
  });
  assert.equal(installed.status, 0, `Pi package installation failed: ${installed.stderr}`);
  const fixturePath = path.join(root, 'fixture.ts');
  const fixture = version => `export default function(pi) {
    pi.registerCommand('fixture-seed', { description: 'Fixture version ${version}', handler: async () => {
      pi.sendMessage({ customType: 'orca-reload-test', content: 'Isolated seed message', display: false }, { triggerTurn: false });
    } });
  }`;
  await writeFile(fixturePath, fixture(1));
  const cli = rpcProcess([
    '--mode', 'rpc', '--no-session', '--no-mcp', '--no-skills',
    '--no-prompt-templates', '--no-context-files',
    '--extension', fixturePath, '--skill', skills, '--provider', 'google', '--model', 'gemini-2.5-flash', '--thinking', 'low',
  ], { cwd: root, env });
  t.after(async () => {
    await cli.close();
    await rm(root, { recursive: true, force: true });
  });
  const firstCommands = await cli.request('get_commands');
  assert.ok(firstCommands.commands.some(command => command.name === 'reload-orca'));
  assert.ok(!firstCommands.commands.some(command => command.name === 'orca-reload'), 'do not retain the old command alias');
  const seeded = await cli.request('prompt', { message: '/fixture-seed' });
  assert.equal(seeded.disposition, 'handled');
  const before = await cli.request('get_state');
  const messages = await cli.request('get_messages');
  assert.ok(messages.messages.length > 0);
  assert.equal(before.model.provider, 'google');
  assert.equal(before.model.id, 'gemini-2.5-flash');

  for (let version = 2; version <= 3; version++) {
    await writeFile(fixturePath, fixture(version));
    const directory = path.join(skills, `probe-${version}`);
    await mkdir(directory);
    await writeFile(path.join(directory, 'SKILL.md'), `---\nname: probe-${version}\ndescription: Isolated reload test fixture\n---\nTest fixture.\n`);
    const previousCount = cli.events.length;
    let commandReturned = false;
    const reply = cli.request('prompt', { message: '/reload-orca' }).then(result => {
      commandReturned = true;
      return result;
    });
    const card = await cli.waitFor(record => record.type === 'extension_ui_request' && record.method === 'select'
      && cli.events.indexOf(record) >= previousCount && record.title.startsWith('Reload completed'));
    assert.deepEqual(card.options, ['OK']);
    await cli.request('get_state');
    assert.deepEqual(cli.autoCancelledDialogs, [], 'Orca must not auto-cancel the result card');
    assert.equal(commandReturned, false, 'the command must remain pending until acknowledgment');
    cli.send(version === 2
      ? { type: 'extension_ui_response', id: card.id, value: 'OK' }
      : { type: 'extension_ui_response', id: card.id, cancelled: true });
    assert.equal((await reply).disposition, 'handled');
    const after = await cli.request('get_state');
    assert.equal(after.sessionId, before.sessionId);
    assert.deepEqual(after.model, before.model);
    assert.equal(after.thinkingLevel, before.thinkingLevel);
    assert.deepEqual(await cli.request('get_messages'), messages);
    const catalog = await cli.request('get_commands');
    assert.equal(catalog.commands.find(command => command.name === 'fixture-seed').description, `Fixture version ${version}`);
    assert.ok(catalog.commands.some(command => command.name === `skill:probe-${version}`));
  }
  assert.equal(cli.events.some(record => record.type === 'agent_start'), false, 'reload must not start inference');
});
