// Replaced with the complete resource inventory by tool/prepare_web.mjs.
const build = /* BUILD_INVENTORY */ null;
const scope = self.registration.scope;
const prefix = `moja-biblioteka:${scope}:`;
const cacheName = `${prefix}${build?.revision}`;
const urls = new Set(build?.files.map(path => new URL(path, scope).href));

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    if (!build) throw new Error('Missing production offline inventory');
    const cache = await caches.open(cacheName);
    const pending = Array.from(urls);
    try {
      while (pending.length) {
        await cache.addAll(pending.splice(0, 8)
          .map(url => new Request(url, { cache: 'reload' })));
      }
    } catch (error) {
      await caches.delete(cacheName);
      throw error;
    }
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(prefix) && name !== cacheName) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('message', event => {
  if (event.data !== 'offline-ready' || !event.ports[0]) return;
  event.waitUntil((async () => {
    try {
      const cache = await caches.open(cacheName);
      const stored = new Set((await cache.keys()).map(request => request.url));
      event.ports[0].postMessage(Boolean(build) && [...urls].every(url => stored.has(url)));
    } catch (_) {
      event.ports[0].postMessage(false);
    }
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const request = new URL(event.request.url);
  const index = new URL('index.html', scope);
  const root = new URL(scope);
  const isEntry = event.request.mode === 'navigate' && request.origin === root.origin
    && (request.pathname === root.pathname || request.pathname === index.pathname);
  const key = isEntry ? index.href : request.href;
  if (!urls.has(key)) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    return (await cache.match(key)) ?? fetch(event.request);
  })());
});
