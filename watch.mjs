import { watch } from 'node:fs';
import { readdir, rename } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const executable = join(directory, 'projector-overlay');
const pendingExecutable = join(directory, 'projector-overlay.next');
let overlay;
let compiler;
let rebuilding = false;
let requested = false;
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

async function rebuild() {
  requested = true;
  if (rebuilding || stopping) return;
  rebuilding = true;
  try {
    while (requested && !stopping) {
      requested = false;
      const sources = (await readdir(directory))
        .filter((name) => name.endsWith('.swift'))
        .sort()
        .map((name) => join(directory, name));
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
      if (stopping) break;
      if (!succeeded) {
        console.error('Build failed. Save a Swift file to retry.');
        continue;
      }
      if (requested) continue;
      await rename(pendingExecutable, executable);
      await stopProcess(overlay);
      if (stopping) break;
      overlay = spawn(executable, process.argv.slice(2), { stdio: 'inherit' });
      overlay.once('error', (error) => console.error(error.message));
      console.log('Overlay restarted. Watching Swift files. Ctrl+C to stop.');
    }
  } catch (error) {
    console.error(error);
  } finally {
    rebuilding = false;
  }
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
  await Promise.all([stopProcess(compiler), stopProcess(overlay)]);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
watcher.on('error', (error) => {
  console.error(error);
  void shutdown();
});
void rebuild();
