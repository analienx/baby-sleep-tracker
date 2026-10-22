#!/usr/bin/env python3
"""Build a versioned, same-origin-only offline shell for Little Rest PWA.

No Firebase or cross-origin responses are cached. Must run after flutter build.
"""
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
if not (root / "main.dart.js").exists():
    sys.exit("Run flutter build web --pwa-strategy=none first.")
files = sorted(
    "/" + f.relative_to(root).as_posix()
    for f in root.rglob("*")
    if f.is_file()
    and not f.name.endswith((".map", ".txt"))
    and f.name not in ("pwa-sw.js",)
    and ".well-known" not in f.parts
)
size = sum((root / f[1:]).stat().st_size for f in files)
if size > 45 * 1024 * 1024:
    sys.exit("PWA cache over 45 MB; review renderer/download sizes.")
digest = hashlib.sha256()
for file in files:
    digest.update(file.encode())
    digest.update(hashlib.sha256((root / file[1:]).read_bytes()).digest())
version = digest.hexdigest()[:16]
sw = """
// Generated with scripts/generate_pwa_worker.py. Do not cache Firebase data.
const CACHE = 'little-rest-shell-%s';
const ASSETS = %s;
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS))
    .then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(
    keys.filter(k => k.startsWith('little-rest-shell-') && k !== CACHE)
      .map(k => caches.delete(k))
  )).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return; // NEVER cache Firebase calls.
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() =>
      caches.match('/index.html')));
    return;
  }
  event.respondWith(caches.match(event.request).then(cached =>
    cached || fetch(event.request)));
});
""" % (version, json.dumps(files, ensure_ascii=False, separators=(",", ":")))
(root / "pwa-sw.js").write_text(sw, encoding="utf-8")
print(f"Offline shell {version}: {len(files)} local files, {size:,} bytes")
