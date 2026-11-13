import { watch } from 'node:fs';
import { readdir, rename } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { format } from 'node:util';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const executable = join(directory, 'projector-overlay');
const pendingExecutable = join(directory, 'projector-overlay.next');
const launchArgs = process.argv.slice(2);
const liveArgs = launchArgs.filter((arg) => arg !== '--demo' && arg !== '--full-demo');
const input = process.stdin;
const interactive = input.isTTY && typeof input.setRawMode === 'function';
const output = process.stdout;
const fixedHeader = interactive && output.isTTY && process.env.TERM !== 'dumb';
let headerActive = false;
const previousRawMode = input.isRaw ?? false;
let overlayArgs = launchArgs;
let fullDemo = launchArgs.includes('--full-demo');
let overlay;
let compiler;
let running = false;
let buildRequested = false;
let restartRequested = false;
let hasBuild = false;
let stopping = false;
let suspended = false;
let debounce;
const pendingStops = new WeakMap();

function log(...values) {
  output.write(format(...values) + '\n');
}

function forwardLog(stream) {
  // Keep parser state across chunks, including OSC and other control strings.
  let state = 'text';
  stream.setEncoding('utf8');
  stream.on('data', (chunk) => {
    let clean = '';
    for (const char of chunk) {
      const code = char.charCodeAt(0);
      if (state === 'string' || state === 'stringEscape') {
        if (char === '\x07' || char === '\x9c' || (state === 'stringEscape' && char === '\\')) {
          state = 'text';
        } else {
          state = char === '\x1b' ? 'stringEscape' : 'string';
        }
      } else if (char === '\x1b') {
        state = 'escape';
      } else if (state === 'escape') {
        if (char === '[') state = 'csi';
        else if (']PX^_'.includes(char)) state = 'string';
        else if (code >= 0x30 && code <= 0x7e) state = 'text';
      } else if (state === 'csi') {
        if (code >= 0x40 && code <= 0x7e) state = 'text';
      } else if (char === '\x9b') {
        state = 'csi';
      } else if ('\x90\x98\x9d\x9e\x9f'.includes(char)) {
        state = 'string';
      } else if (char === '\n' || char === '\t' || (code >= 0x20 && (code < 0x7f || code > 0x9f))) {
        clean += char;
      }
    }
    if (clean) output.write(clean);
  });
}

function spawnLogged(command, args) {
  const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  forwardLog(child.stdout);
  forwardLog(child.stderr);
  return child;
}

function drawHeader() {
  if (!fixedHeader) return;
  if (output.rows < 4) {
    if (headerActive) output.write('\x1b[r');
    headerActive = false;
    return;
  }
  const hint = 'd Demo | r Reload | s Suspend | Ctrl+C Quit';
  const status = suspended ? 'Suspended — s to resume' : 'Watching Swift files';
  const width = Math.max(1, output.columns - 1);
  output.write('\x1b7\x1b[r\x1b[1;1H\x1b[2K' + hint.slice(0, width)
    + '\x1b[2;1H\x1b[2K' + status.slice(0, width)
    + '\x1b[3;' + output.rows + 'r'
    + (headerActive ? '\x1b8' : '\x1b[3;1H'));
  headerActive = true;
}

function stopProcess(child) {
  if (!child?.pid || child.exitCode !== null || child.signalCode !== null) return Promise.resolve();
  const pending = pendingStops.get(child);
  if (pending) return pending;
  const stopped = new Promise((resolve) => {
    const timeout = setTimeout(() => child.kill('SIGKILL'), 2000);
    child.once('exit', () => {
      clearTimeout(timeout);
      resolve();
    });
    child.kill('SIGTERM');
  });
  pendingStops.set(child, stopped);
  return stopped;
}

function rebuild() {
  buildRequested = true;
  void update();
}

async function update() {
  if (running || stopping) return;
  running = true;
  try {
    while (!stopping) {
      if (suspended) {
        await stopProcess(overlay);
        if (suspended || stopping) break;
      }
      if (!buildRequested && !restartRequested) break;
      if (buildRequested) {
        buildRequested = false;
        if (await build()) {
          if (stopping) break;
          await rename(pendingExecutable, executable);
          hasBuild = true;
          restartRequested = true;
        }
        if (buildRequested || suspended) continue;
      }
      if (!restartRequested || !hasBuild || stopping) break;
      await stopProcess(overlay);
      if (buildRequested || suspended) continue;
      if (stopping) break;
      restartRequested = false;
      overlay = spawnLogged(executable, overlayArgs);
      overlay.once('error', (error) => log(error.message));
      log('Overlay restarted. Watching Swift files.');
    }
  } catch (error) {
    log(error);
  } finally {
    running = false;
  }
}

async function build() {
  const sources = (await readdir(directory))
    .filter((name) => name.endsWith('.swift'))
    .sort()
    .map((name) => join(directory, name));
  if (stopping) return false;
  log('Building Swift overlay…');
  const succeeded = await new Promise((resolve) => {
    compiler = spawnLogged('xcrun', [
      '--sdk', 'macosx', 'swiftc', '-O', '-parse-as-library',
      '-target', 'arm64-apple-macosx14.0',
      '-module-cache-path', join(directory, 'cache'),
      ...sources, '-o', pendingExecutable,
    ]);
    compiler.once('error', (error) => {
      log(error.message);
      resolve(false);
    });
    compiler.once('close', (code) => resolve(code === 0));
  });
  compiler = undefined;
  if (!succeeded && !stopping) {
    log('Build failed. Save a Swift file to retry.');
  }
  return succeeded;
}

const watcher = watch(directory, (_event, filename) => {
  if (filename && !filename.toString().endsWith('.swift')) return;
  clearTimeout(debounce);
  debounce = setTimeout(rebuild, 150);
});

async function shutdown() {
  if (stopping) return;
  stopping = true;
  clearTimeout(debounce);
  watcher.close();
  if (interactive) {
    output.off('resize', drawHeader);
    input.off('data', onKey);
    input.setRawMode(previousRawMode);
    input.pause();
  }
  await Promise.all([stopProcess(compiler), stopProcess(overlay)]);
  if (headerActive) {
    output.write('\x1b[r\x1b[1;1H\x1b[2K\x1b[2;1H\x1b[2K\x1b[' + output.rows + ';1H');
  }
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
watcher.on('error', (error) => {
  log(error);
  void shutdown();
});

function onKey(chunk) {
  for (const key of chunk.toString()) {
    if (key === '\x03') {
      void shutdown();
      return;
    }
    if (key === 's') {
      suspended = !suspended;
      if (suspended) void stopProcess(overlay);
      drawHeader();
      if (!headerActive) log(suspended ? 'Preview suspended.' : 'Preview resumed.');
      if (!suspended && !hasBuild) buildRequested = true;
    } else if (key === 'd') {
      fullDemo = !fullDemo;
      overlayArgs = fullDemo ? [...liveArgs, '--full-demo'] : liveArgs;
      log(fullDemo ? 'Demo quotas enabled.' : 'Live quotas enabled.');
    } else if (key !== 'r') {
      continue;
    }
    restartRequested = true;
  }
  void update();
}

if (interactive) {
  input.setRawMode(true);
  input.on('data', onKey);
  output.on('resize', drawHeader);
  drawHeader();
  if (!headerActive) log('d: toggle demo · r: reload · s: suspend · Ctrl+C: quit');
}
rebuild();
