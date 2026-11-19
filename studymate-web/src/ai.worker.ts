import { env, pipeline } from '@huggingface/transformers';
// CPU/WASM works without WebGPU, cross-origin isolation or a powerful GPU.
env.allowLocalModels = false;
env.useBrowserCache = true;
env.backends.onnx.wasm!.numThreads = 1;
env.backends.onnx.wasm!.wasmPaths = new URL('./', self.location.href).href;
let generator: any;
const revision = '311454e83bc784267fd7eef5940ee854144abbec';
async function load() {
  if (!generator) generator = await pipeline('text2text-generation', 'Xenova/flan-t5-small', {
    dtype: 'q8', device: 'wasm', revision,
    progress_callback: (p: any) => { if (p.status === 'progress') self.postMessage({type:'progress', text:`Downloading ${p.file?.split('/').pop() ?? 'model'} · ${Math.round(p.progress ?? 0)}%`}); },
  });
  return generator;
}
self.onmessage = async ({data}) => {
  try {
    const model = await load();
    if (data.type === 'load') {
      await model('Answer the question: What is 1 plus 1?', {max_new_tokens: 4});
      self.postMessage({type:'ready'}); return;
    }
    const output = await model(data.prompt, { max_new_tokens: data.maxTokens ?? 100, do_sample: false, repetition_penalty: 1.15 });
    self.postMessage({type:'result', id: data.id, text: output[0].generated_text});
  } catch (error) {
    generator = undefined;
    self.postMessage({type:'error', id:data.id, text: error instanceof Error ? error.message : String(error)});
  }
};
