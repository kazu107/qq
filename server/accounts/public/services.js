"use strict";
(() => {
  const writer = crypto.randomUUID();
  let overlay, panel, title, close, previousFocus, current, listener;
  const frames = new Map();
  const snapshot = { state: "starting", blocked: false };
  function initialize() {
    if (overlay) return;
    const style = document.createElement("style");
    style.textContent = `#qq-services{position:fixed;inset:0;z-index:100000;background:#020910bd;backdrop-filter:blur(7px);display:grid;place-items:center;padding:16px;color:#edf2ef;font:16px "Yu Gothic UI",sans-serif}#qq-services[hidden]{display:none}#qq-service-panel{width:min(1180px,100%);height:min(900px,94dvh);display:flex;flex-direction:column;background:#0c1721;border:1px solid #537084;border-top:3px solid #f1c76d;border-radius:16px;box-shadow:0 24px 100px #000a;overflow:hidden}#qq-service-header{display:flex;align-items:center;gap:16px;padding:12px 20px;border-bottom:1px solid #344c5c}#qq-service-header strong{flex:1}#qq-service-close{border:1px solid #577080;border-radius:9px;background:#182b37;color:#f0f4f0;min-width:44px;height:38px;cursor:pointer;font-size:22px}#qq-service-close:disabled{opacity:.35;cursor:wait}#qq-service-panel iframe{width:100%;flex:1;border:0;min-height:0;background:#061019}#qq-service-panel iframe[hidden]{display:none}@media(max-width:600px){#qq-services{padding:5px}#qq-service-panel{height:98dvh;border-radius:10px}}`;
    document.head.append(style);
    overlay = document.createElement("div"); overlay.id = "qq-services"; overlay.hidden = true;
    panel = document.createElement("section"); panel.id = "qq-service-panel"; panel.role = "dialog"; panel.setAttribute("aria-modal", "true"); panel.setAttribute("aria-labelledby", "qq-service-title");
    const header = document.createElement("div"); header.id = "qq-service-header";
    title = document.createElement("strong"); title.id = "qq-service-title";
    close = document.createElement("button"); close.id = "qq-service-close"; close.textContent = "\u00d7"; close.addEventListener("click", hide);
    header.append(title, close); panel.append(header); overlay.append(panel); document.body.append(overlay);
    overlay.addEventListener("click", event => { if (event.target === overlay) hide(); });
    document.addEventListener("keydown", event => {
      if (overlay.hidden) return;
      if (event.key === "Escape") { event.preventDefault(); hide(); }
      if (event.key === "Tab" && event.target === close) { event.preventDefault(); frames.get(current)?.focus(); }
    });
  }
  function hide() {
    if (snapshot.blocked || !overlay) return;
    overlay.hidden = true; previousFocus?.focus(); window.qqAccount?.refresh();
  }
  function open(kind, language = "ja") {
    initialize();
    if (!["account", "rankings"].includes(kind)) return false;
    if (snapshot.blocked) kind = "account";
    current = kind;
    const english = language === "en";
    title.textContent = kind === "account" ? (english ? "Account & Cloud Save" : "アカウント・クラウド保存") : (english ? "Infinite Rankings" : "無限ランキング");
    close.setAttribute("aria-label", english ? "Return to game" : "ゲームに戻る"); close.disabled = snapshot.blocked;
    const url = `/${kind}?lang=${english ? "en" : "ja"}&embedded=1`;
    if (!frames.has(kind)) {
      const frame = document.createElement("iframe"); frame.title = title.textContent; frame.src = url; frame.dataset.language = language;
      frame.addEventListener("load", () => frame.contentWindow.postMessage({ type: "qq-cloud-state", data: snapshot }, location.origin));
      frames.set(kind, frame); panel.append(frame);
    } else if (frames.get(kind).dataset.language !== language) { frames.get(kind).src = url; frames.get(kind).dataset.language = language; }
    for (const [key, frame] of frames) { frame.hidden = key !== kind; if (key === kind) frame.contentWindow?.postMessage({ type: "qq-service-refresh" }, location.origin); }
    if (overlay.hidden) previousFocus = document.activeElement;
    overlay.hidden = false; close.focus(); return true;
  }
  window.qqServices = { open, close: hide };
  window.qqCloud = {
    stateSnapshot: () => structuredClone(snapshot),
    enableQA: () => new URLSearchParams(location.search).get("cloud_review") === "1",
    writerId: () => writer,
    subscribe(callback) { listener = callback; },
    action(command) { if (listener) listener(JSON.stringify(command)); },
    publish(raw) {
      try { Object.assign(snapshot, JSON.parse(raw)); } catch { return; }
      if (close) close.disabled = !!snapshot.blocked;
      for (const frame of frames.values()) frame.contentWindow?.postMessage({ type: "qq-cloud-state", data: snapshot }, location.origin);
      if (snapshot.blocked) open("account", document.documentElement.lang === "en" ? "en" : "ja");
    },
    async request(method, path, rawBody, owner, callback) {
      try {
        if (!/^\/api\/cloud\/(save|history|claim|lease|release|restore)$/.test(path) && path !== "/api/account/logout") throw Error();
        const headers = { "X-QQ-Account": owner, "X-QQ-Writer": writer };
        if (method !== "GET") {
          const profile = await (await fetch("/api/account", { credentials: "same-origin", cache: "no-store", signal: AbortSignal.timeout(8000) })).json();
          if (!profile.authenticated || profile.user?.id !== owner) { callback(JSON.stringify({ error: "account_changed" })); return; }
          headers["Content-Type"] = "application/json"; headers["X-CSRF-Token"] = profile.csrfToken;
        }
        const response = await fetch(path, { method, credentials: "same-origin", cache: "no-store", signal: AbortSignal.timeout(20000), headers, ...(method !== "GET" ? { body: rawBody } : {}) });
        callback(JSON.stringify(await response.json()));
      } catch { callback(JSON.stringify({ error: "network_error" })); }
    },
  };
  window.addEventListener("message", event => {
    if (event.origin !== location.origin || !Array.from(frames.values()).some(frame => frame.contentWindow === event.source)) return;
    if (event.data?.type === "qq-service-close") hide();
    if (event.data?.type === "qq-service-open") open(event.data.kind, event.data.language);
    if (event.data?.type === "qq-cloud-action") window.qqCloud.action(event.data.command);
    if (event.data?.type === "qq-account-changed") window.qqAccount?.refresh();
    if (event.data?.type === "qq-auth-start") window.qqAccount?.oauth(event.data.provider, event.data.language);
  });
})();
