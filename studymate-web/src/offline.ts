export const isPreview = /(?:devinapps\.com|devin\.ai|devinusercontent\.com)$/.test(location.hostname) || location.hostname.includes('--');
export async function prepareOffline(onStatus:(text:string)=>void) {
  if (isPreview) { onStatus('Preview only · offline installation needs a normal HTTPS host'); return; }
  if (!('serviceWorker' in navigator)) { onStatus('Offline installation is not supported in this browser'); return; }
  try {
    await navigator.serviceWorker.register(new URL('sw.js', document.baseURI), {type:'classic'});
    await Promise.race([
      navigator.serviceWorker.ready,
      new Promise((_, reject) => setTimeout(() => reject(new Error('Offline setup timed out')), 45000)),
    ]);
    const check = () => { if (navigator.serviceWorker.controller) onStatus('Ready for offline study'); else onStatus('Saved for offline · reopen once to finish'); };
    check(); navigator.serviceWorker.addEventListener('controllerchange', check);
  } catch { onStatus('Offline save failed · check your connection and reopen'); }
}
