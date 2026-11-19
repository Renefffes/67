import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { runInNewContext } from 'node:vm';

test('cached modules load offline despite the host varying responses by Origin', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'studymate-origin-'));
  try {
    await mkdir(join(dir, 'dist/assets'), { recursive: true });
    await mkdir(join(dir, 'node_modules/onnxruntime-web/dist'), { recursive: true });
    await writeFile(join(dir, 'dist/index.html'), '<title>StudyMate</title>');
    execFileSync(process.execPath, [fileURLToPath(new URL('../scripts/offline.mjs', import.meta.url))], { cwd: dir });
    const code = await readFile(join(dir, 'dist/sw.js'), 'utf8');
    const request = new Request('https://example.org/assets/app.js', { headers: { Origin: 'https://example.org' }, mode: 'cors' });
    let handler: (event: { request: Request; respondWith: (promise: Promise<Response>) => void }) => void = () => {};
    runInNewContext(code, {
      URL,
      self: { registration: { scope: 'https://example.org/' }, location: { origin: 'https://example.org' }, addEventListener: (name: string, fn: typeof handler) => { if (name === 'fetch') handler = fn; } },
      caches: { open: async () => ({ match: async (req: Request, options: { ignoreVary?: boolean }) => {
        // Cache.addAll stored a request without Origin. Honor the real Vary contract.
        if (req.headers.has('Origin') && !options.ignoreVary) return undefined;
        return new Response('cached module', { headers: { Vary: 'Origin' } });
      } }) },
      fetch: async () => { throw new Error('Network is offline'); },
    });
    let response: Promise<Response> = Promise.reject(new Error('Worker did not handle the request'));
    response.catch(() => {});
    handler({ request, respondWith: promise => { response = promise; } });
    assert.equal(await (await response).text(), 'cached module');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('updating one installation preserves offline files for another scope', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'studymate-worker-'));
  try {
    await mkdir(join(dir, 'dist/assets'), { recursive: true });
    await mkdir(join(dir, 'node_modules/onnxruntime-web/dist'), { recursive: true });
    await writeFile(join(dir, 'dist/index.html'), '<title>StudyMate</title>');
    execFileSync(process.execPath, [fileURLToPath(new URL('../scripts/offline.mjs', import.meta.url))], { cwd: dir });
    const code = await readFile(join(dir, 'dist/sw.js'), 'utf8');
    const scope = 'https://example.org/studymate/';
    const prefix = `studymate:${encodeURIComponent(scope)}:`;
    const other = `studymate:${encodeURIComponent('https://example.org/beta/')}:previous`;
    const stored = new Set([prefix + 'previous', other, 'another-app']);
    const handlers: Record<string, (event: { waitUntil: (promise: Promise<unknown>) => void }) => void> = {};
    runInNewContext(code, {
      URL,
      self: { registration: { scope }, clients: { claim: async () => {} }, addEventListener: (name: string, fn: typeof handlers[string]) => { handlers[name] = fn; } },
      caches: { keys: async () => [...stored], delete: async (key: string) => stored.delete(key) },
    });
    let activation: Promise<unknown> = Promise.resolve();
    handlers.activate({ waitUntil: promise => { activation = promise; } });
    await activation;
    assert.equal(stored.has(prefix + 'previous'), false);
    assert.equal(stored.has(other), true);
    assert.equal(stored.has('another-app'), true);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
