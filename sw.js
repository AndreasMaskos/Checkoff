// ponytail: stale-while-revalidate over the app shell. Serves instantly offline,
// picks up a new version on the next load. Bump CACHE if that ever needs forcing.
const CACHE = 'checkoff-v3';
const SHELL = ['./', 'index.html', 'config.js', 'manifest.json', 'icon.svg', 'icon-192.png', 'icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;   // let Supabase et al. through

  // The page itself is network-first: a deploy is then live on the next load
  // rather than the one after, which is how "my change isn't there" happens.
  // Offline still works — the cached copy is the fallback.
  if (e.request.mode === 'navigate' || e.request.destination === 'document') {
    e.respondWith(caches.open(CACHE).then(async cache => {
      try {
        const fresh = await fetch(e.request);
        cache.put(e.request, fresh.clone());
        return fresh;
      } catch {
        return (await cache.match(e.request)) || cache.match('./');
      }
    }));
    return;
  }

  e.respondWith(caches.open(CACHE).then(async cache => {
    const hit = await cache.match(e.request);
    const fresh = fetch(e.request).then(res => { res.ok && cache.put(e.request, res.clone()); return res; });
    return hit || fresh;
  }));
});
