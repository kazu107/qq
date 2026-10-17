"use strict";
(() => {
  window.qqRanked = {
    open(language) { return !!window.qqServices?.open('rankings', language); },
    async request(method, path, rawBody, callback) {
      try {
        if (!/^\/api\/ranked\//.test(path)) throw new Error();
        const headers = {};
        if (method === 'POST') {
          const account = await (await fetch('/api/account', { credentials:'same-origin', cache:'no-store' })).json();
          if (!account.authenticated || account.needsUsername) { callback(JSON.stringify({ error:'login_required' })); return; }
          headers['Content-Type'] = 'application/json'; headers['X-CSRF-Token'] = account.csrfToken;
        }
        const response = await fetch(path, { method, credentials:'same-origin', headers, cache:'no-store', body:method === 'POST' ? rawBody : undefined, signal:AbortSignal.timeout(30000) });
        callback(JSON.stringify(await response.json()));
      } catch { callback(JSON.stringify({ error:'network_error' })); }
    },
  };
})();
