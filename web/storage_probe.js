// Real IndexedDB smoke test before allowing offline-capable sleep recording.
// Opening a database is necessary but not sufficient proof of permanent storage.
window.littleRestCheckStorage = function () {
  return new Promise(resolve => {
    if (!window.indexedDB) { resolve(false); return; }
    let request;
    try { request = indexedDB.open('little-rest-storage-probe', 1); }
    catch (_) { resolve(false); return; }
    request.onerror = () => resolve(false);
    request.onblocked = () => resolve(false);
    request.onsuccess = () => {
      try {
        const db = request.result;
        db.close();
        resolve(true);
      } catch (_) { resolve(false); }
    };
  });
};
