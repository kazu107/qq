"use strict";

(() => {
  let status = { available:false, authenticated:false, needsUsername:false, user:null, providers:[], reason:"loading" };
  const listeners = new Set();
  let pending = null, popup = null, poll = null;
  const broadcast = () => { for (const listener of listeners) { try { listener(JSON.stringify(status)); } catch {} } };
  async function refresh() {
    if (pending) return pending;
    pending = (async () => {
      try {
        const response = await fetch("/api/account", { credentials:"same-origin", cache:"no-store", signal:AbortSignal.timeout(6000) });
        const data = await response.json();
        status = { available:!!data.available, authenticated:!!data.authenticated, needsUsername:!!data.needsUsername,
          user:data.user ? { id:data.user.id, username:data.user.username } : null, canDeveloper:!!data.canDeveloper,
          providers:Array.isArray(data.providers) ? data.providers : [], reason:data.reason || (response.ok ? "" : "unavailable") };
      } catch { status = { available:false, authenticated:false, needsUsername:false, user:null, providers:[], reason:"unavailable" }; }
      broadcast();
    })().finally(() => { pending = null; });
    return pending;
  }
  window.qqAccount = {
    refresh,
    subscribe(listener) { listeners.add(listener); listener(JSON.stringify(status)); },
    open(language) {
      return !!window.qqServices?.open("account", language);
    },
    oauth(provider, language) {
      if (!["google", "github"].includes(provider)) return false;
      popup = window.open(`/auth/${provider}/start?lang=${language === "en" ? "en" : "ja"}`, "qq-auth", "popup,width=620,height=780");
      if (!popup) return false;
      clearInterval(poll);
      let attempts = 0;
      poll = setInterval(() => {
        refresh();
        if (++attempts >= 60 || popup?.closed) { clearInterval(poll); poll = null; }
      }, 2000);
      return true;
    },
  };
  window.addEventListener("message", event => {
    if (event.origin === location.origin && event.source === popup && event.data?.type === "qq-account-changed") refresh();
  });
  window.addEventListener("focus", refresh);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
  refresh();
})();
