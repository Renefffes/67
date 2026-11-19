import { readdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
// Ship the ONNX runtime locally rather than depending on a CDN offline.
const runtime = 'node_modules/onnxruntime-web/dist';
for (const name of await readdir(runtime)) {
  if (name.startsWith('ort-wasm-simd-threaded') && /\.(wasm|mjs)$/.test(name)) await copyFile(`${runtime}/${name}`, `dist/assets/${name}`);
}
async function walk(dir) { const out=[];for(const f of await readdir(dir,{withFileTypes:true})){if(f.isDirectory())out.push(...await walk(`${dir}/${f.name}`));else out.push(`${dir}/${f.name}`);}return out; }
const files=(await walk('dist')).filter(f=>!f.endsWith('sw.js')&&!f.endsWith('.map'));
const hash=createHash('sha256');for(const f of files)hash.update(await readFile(f));
const version=hash.digest('hex').slice(0,12);
// Cache the complete app including its worker/runtime before claiming offline readiness.
const urls=files.map(f=>'./'+f.slice(5));urls.push('./');
await writeFile('dist/sw.js', `const CACHE='studymate-${version}';
const FILES=${JSON.stringify(urls)};
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(FILES)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('studymate-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin)return;
 event.respondWith(caches.open(CACHE).then(async cache=>{
  const saved=await cache.match(event.request,{ignoreSearch:true});
  if(saved)return saved;
  try{return await fetch(event.request);}catch(error){if(event.request.mode==='navigate')return (await cache.match('./index.html'));throw error;}
 }));
});\n`);
console.log(`Offline shell ${version}: ${files.length} files cached. Model weights are downloaded separately with consent.`);
