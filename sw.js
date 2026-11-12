/* Stick2It: makes repeat visits fast on a weak signal.
   - The page itself: always fetched fresh when there's signal (so updates show right away).
     If the signal is too slow (3.5 s) or gone, the copy from the last visit opens instantly.
   - Fonts and code libraries (their addresses carry version numbers): kept after the first visit.
   - Orders, statuses and anything from the database: never stored, always live. */
const CACHE = 'stick2it-v1';
const KEEP = [/^https:\/\/api\.fontshare\.com\//, /^https:\/\/cdn\.fontshare\.com\//, /^https:\/\/fonts\.googleapis\.com\//, /^https:\/\/fonts\.gstatic\.com\//,
  /^https:\/\/cdn\.jsdelivr\.net\/npm\/[^/]+@\d/, /^https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/[^/]+\/\d/];

self.addEventListener('install', e => { self.skipWaiting(); e.waitUntil(caches.open(CACHE).then(c => c.add('/').catch(() => {}))); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request; if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // the page: fresh first, saved copy if the signal is slow or gone
  if (req.mode === 'navigate' && url.origin === location.origin) {
    e.respondWith((async () => {
      const cache = await caches.open(CACHE);
      const net = fetch(req).then(r => { if (r.ok) cache.put('/', r.clone()); return r; });
      try { return await Promise.race([net, new Promise((_, no) => setTimeout(() => no(new Error('slow')), 3500))]); }
      catch { const saved = await cache.match('/'); if (saved) { net.catch(() => {}); return saved; } return net; }
    })());
    return;
  }
  // fonts and versioned libraries: from the phone after the first visit
  if (KEEP.some(r => r.test(req.url))) {
    e.respondWith(caches.open(CACHE).then(async cache => {
      const hit = await cache.match(req); if (hit) return hit;
      const r = await fetch(req); if (r.ok || r.type === 'opaque') cache.put(req, r.clone()); return r;
    }));
    return;
  }
  // the site's own pictures (icons, lock page art): saved copy now, refreshed in the background
  if (url.origin === location.origin && /\.(png|webp|svg|ico|webmanifest)$/.test(url.pathname)) {
    e.respondWith(caches.open(CACHE).then(async cache => {
      const hit = await cache.match(req), net = fetch(req).then(r => { if (r.ok) cache.put(req, r.clone()); return r; }).catch(() => hit);
      return hit || net;
    }));
  }
  // everything else (the database, uploads, order lookups) goes straight to the network
});
