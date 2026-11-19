import { test } from 'node:test';
import assert from 'node:assert/strict';
import { aiReady, connectAI, generate, loadAI, stopAI } from '../src/ai.ts';

test('stopping or failing AI clears displayed readiness and releases the pending generation', async () => {
  const original = globalThis.Worker;
  let current: FakeWorker;
  class FakeWorker {
    onmessage?: (event: any) => void;
    onerror?: () => void;
    terminated = false;
    constructor() { current = this; }
    postMessage() {}
    terminate() { this.terminated = true; }
    emit(data: unknown) { this.onmessage?.({data}); }
  }
  globalThis.Worker = FakeWorker as unknown as typeof Worker;
  const readiness: boolean[] = [];
  const statuses: string[] = [];
  connectAI(text => statuses.push(text), ready => readiness.push(ready));
  try {
    loadAI();
    current!.emit({type:'ready'});
    assert.equal(aiReady,true);
    assert.equal(readiness.at(-1),true);
    const interrupted = assert.rejects(generate('A pending question'),/Generation stopped/);
    stopAI();
    await interrupted;
    assert.equal(current!.terminated,true);
    assert.equal(aiReady,false);
    assert.equal(readiness.at(-1),false);
    assert.match(statuses.at(-1)!,/AI stopped/);

    loadAI();
    current!.emit({type:'ready'});
    const failed = assert.rejects(generate('Another question'),/Out of memory/);
    current!.emit({type:'error',text:'Out of memory'});
    await failed;
    assert.equal(aiReady,false);
    assert.equal(readiness.at(-1),false);
  } finally {
    stopAI();
    globalThis.Worker = original;
  }
});
