let worker: Worker | undefined;
let active: { resolve: (s:string)=>void; reject: (e:Error)=>void } | undefined;
let onStatus = (_text:string) => {};
let onReady = () => {};
export let aiReady = false;
export function connectAI(status: (text:string)=>void, ready: ()=>void) { onStatus = status; onReady = ready; }
function getWorker() {
  if (!worker) {
    worker = new Worker(new URL('./ai.worker.ts', import.meta.url), {type:'module'});
    worker.onmessage = ({data}) => {
      if (data.type === 'progress') onStatus(data.text);
      if (data.type === 'ready') { aiReady = true; onStatus('Local AI is ready on this device'); onReady(); }
      if (data.type === 'result') { active?.resolve(data.text); active = undefined; }
      if (data.type === 'error') { onStatus('AI could not load. Check your connection or storage and retry. Notes helper still works.'); active?.reject(new Error(data.text)); active = undefined; }
    };
    worker.onerror = () => { onStatus('This browser could not start local AI. Notes helper is still available.'); active?.reject(new Error('AI worker failed')); active = undefined; worker?.terminate(); worker = undefined; aiReady = false; };
  }
  return worker;
}
export function loadAI() { onStatus('Loading local AI… The first download is about 100 MB, plus its runtime.'); getWorker().postMessage({type:'load'}); }
export function generate(prompt:string, maxTokens = 100): Promise<string> {
  if (active) return Promise.reject(new Error('AI is busy. Please wait.'));
  return new Promise((resolve,reject) => { active={resolve,reject}; getWorker().postMessage({type:'generate', id:crypto.randomUUID(), prompt, maxTokens}); });
}
export function stopAI() { worker?.terminate(); worker = undefined; aiReady = false; active?.reject(new Error('Generation stopped')); active = undefined; }
