// Stick2XU: lets phones install the site like an app. It doesn't cache anything,
// so customers always get the latest version of the site.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
