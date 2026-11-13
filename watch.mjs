import { watch } from 'node:fs';
import { readdir, rename } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const executable = join(directory, 'projector-overlay');
const pendingExecutable = join(directory, 'projector-overlay.next');
const launchArgs = process.argv.slice(2);
const liveArgs = launchArgs.filter((arg) => arg !== '--demo' && arg !== '--full-demo');
const input = process.stdin;
const interactive = input.isTTY && typeof input.setRawMode === 'function';
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
let debounce;

function stopProcess(child) {
  if (!child?.pid || child.exitCode !== null || child.signalCode !== null) return Promise.resolve();
  return new Promise((resolve) => {
    const timeout = setTimeout(() => child.kill('SIGKILL'), 2000);
    child.once('exit', () => {
      clearTimeout(timeout);
      resolve();
    });
    child.kill('SIGTERM');
  });
}

function rebuild() {
  buildRequested = true;
  void update();
}

async function update() {
  if (running || stopping) return;
  running = true;
  try {
    while ((buildRequested || restartRequested) && !stopping) {
      if (buildRequested) {
        buildRequested = false;
        if (await build()) {
          if (stopping) break;
          await rename(pendingExecutable, executable);
          hasBuild = true;
          restartRequested = true;
        }
        if (buildRequested) continue;
      }
      if (!restartRequested || !hasBuild || stopping) break;
      await stopProcess(overlay);
      if (buildRequested) continue;
      if (stopping) break;
      restartRequested = false;
      overlay = spawn(executable, overlayArgs, { stdio: ['ignore', 'inherit', 'inherit'] });
      overlay.once('error', (error) => console.error(error.message));
      console.log('Overlay restarted. Watching Swift files.');
    }
  } catch (error) {
    console.error(error);
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
  console.log('Building Swift overlay…');
  const succeeded = await new Promise((resolve) => {
    compiler = spawn('xcrun', [
      '--sdk', 'macosx', 'swiftc', '-O', '-parse-as-library',
      '-target', 'arm64-apple-macosx14.0',
      '-module-cache-path', join(directory, 'cache'),
      ...sources, '-o', pendingExecutable,
    ], { stdio: 'inherit' });
    compiler.once('error', (error) => {
      console.error(error.message);
      resolve(false);
    });
    compiler.once('exit', (code) => resolve(code === 0));
  });
  compiler = undefined;
  if (!succeeded && !stopping) {
    console.error('Build failed. Save a Swift file to retry.');
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
    input.off('data', onKey);
    input.setRawMode(previousRawMode);
    input.pause();
  }
  await Promise.all([stopProcess(compiler), stopProcess(overlay)]);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
watcher.on('error', (error) => {
  console.error(error);
  void shutdown();
});

function onKey(chunk) {
  for (const key of chunk.toString()) {
    if (key === '\x03') {
      void shutdown();
      return;
    }
    if (key === 'd') {
      fullDemo = !fullDemo;
      overlayArgs = fullDemo ? [...liveArgs, '--full-demo'] : liveArgs;
      console.log(fullDemo ? 'Demo quotas enabled.' : 'Live quotas enabled.');
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
  console.log('d: toggle demo · r: reload · Ctrl+C: quit');
}
rebuild();
