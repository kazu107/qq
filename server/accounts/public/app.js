"use strict";

(() => {
  const language = new URLSearchParams(location.search).get("lang") === "en" ? "en" : "ja";
  const embedded = window.parent !== window;
  const initial = new URLSearchParams(location.search);
  if (window.opener && (initial.has("result") || initial.has("error"))) {
    try { window.opener.postMessage({ type:"qq-account-changed" }, location.origin); window.close(); } catch {}
  }
  if (embedded) document.body.classList.add("embedded");
  if (window.opener) sessionStorage.setItem("qq-account-popup", "1");
  const messages = {
    ja: { title:"アカウント", subtitle:"Google・GitHubでログイン／新規登録します。", google:"Googleで続ける", github:"GitHubで続ける",
      loading:"アカウントを確認中...", guest:"ログイン方法を選んでください。", setup:"ログイン機能は準備中です。ゲームはログインなしで引き続き遊べます。",
      pending:"本人確認が完了しました。ユーザー名を決めて登録してください。", signedIn:"ログインしています。", username:"ユーザー名", register:"登録を完了", identity:"登録済みユーザー名",
      hint:"3〜20文字。日本語・英数字・ハイフン・アンダースコアを使えます。大文字小文字や全角半角の違いだけの名前は重複扱いになります。登録後の変更には対応していません。",
      providerNote:"初回はユーザー名を設定します。GoogleとGitHubは別々のアカウントです。同じメールアドレスでも自動で統合しません。",
      local:"ログイン中の進行はアカウントに保存し、他のデバイスと共有できます。ゲストの進行と端末設定は別に保持します。同期済み表示を確認してから端末を切り替えてください。",
      privacy:"ログイン方法の固定ID、ユーザー名、クラウドの進行データと保存履歴、ランキングの操作記録・結果を保存します。パスワード・メールアドレス・外部サービスのアクセストークンは保存しません。",
      developerAccess:"このアカウントは開発者モードを利用できます。",
      logout:"ログアウト", refresh:"再確認", back:"ゲームに戻る", complete:"登録が完了しました。ゲームに戻れます。", loggedOut:"ログアウトしました。",
      invalid_username:"ユーザー名は3〜20文字の日本語・英数字・ハイフン・アンダースコアで入力してください。予約名は使用できません。",
      username_taken:"そのユーザー名は既に使われています。別の名前を選んでください。", username_already_set:"ユーザー名は既に登録されています。再確認してください。",
      login_required:"セッションが切れました。もう一度ログインしてください。", cancelled:"ログインをキャンセルしました。", invalid_login:"ログインの有効期限が切れたか、別のブラウザで開始されました。最初からやり直してください。",
      login_failed:"ログインできませんでした。時間をおいて、もう一度お試しください。", provider_unavailable:"このログイン方法は現在利用できません。", rate_limited:"操作が多いため、少し待ってから再試行してください。",
      unavailable:"アカウントに接続できません。ゲームのローカルプレイには影響しません。再確認してください。", invalid_csrf:"ページを再読み込みして、もう一度お試しください。" },
    en: { title:"Your Account", subtitle:"Sign in or register with Google or GitHub.", google:"Continue with Google", github:"Continue with GitHub",
      loading:"Checking your account...", guest:"Choose a sign-in method.", setup:"Sign-in is being prepared. You can keep playing without an account.",
      pending:"Identity verified. Choose your username to finish registration.", signedIn:"You are signed in.", username:"Username", register:"Finish registration", identity:"Registered username",
      hint:"3-20 letters/numbers, including Japanese, hyphens or underscores. Case-only and width-only differences are not unique. Usernames cannot currently be changed after registration.",
      providerNote:"First-time users choose a username. Google and GitHub create separate accounts; matching emails are never automatically linked.",
      local:"Signed-in progress is saved to your account and shared across devices. Guest progress and device preferences stay separate. Check that syncing has completed before changing devices.",
      privacy:"We store the provider's stable ID, username, cloud progress and save history, plus Ranked input journals and results. No passwords, email addresses or provider access tokens are stored.",
      developerAccess:"This account can use Developer Mode.",
      logout:"Sign out", refresh:"Check again", back:"Return to game", complete:"Registration complete. You can return to the game.", loggedOut:"You have signed out.",
      invalid_username:"Use 3-20 letters/numbers, hyphens or underscores. Reserved names are unavailable.", username_taken:"That username is already taken. Please choose another.", username_already_set:"Your username is already registered. Check your account again.",
      login_required:"Your session expired. Please sign in again.", cancelled:"Sign-in cancelled.", invalid_login:"This sign-in expired or started in another browser. Please start again.", login_failed:"Sign-in failed. Please try again later.",
      provider_unavailable:"This sign-in method is unavailable.", rate_limited:"Too many attempts. Please wait and try again.", unavailable:"Accounts are temporarily unavailable. Local play is unaffected.", invalid_csrf:"Reload this page and try again." },
  };
  const t = messages[language];
  const el = id => document.getElementById(id);
  let snapshot = null, busy = false, refreshSerial = 0;
  document.documentElement.lang = language;
  document.title = `QueueQuest | ${t.title}`;
  for (const [id, value] of Object.entries({ title:t.title, subtitle:t.subtitle, "google-label":t.google, "github-label":t.github,
    "username-label":t.username, "username-hint":t.hint, "provider-note":t.providerNote, "local-save-note":t.local, "privacy-note":t.privacy,
    register:t.register, "identity-label":t.identity, logout:t.logout, refresh:t.refresh, return:t.back })) el(id).textContent = value;
  function notice(text, error = false) { el("message").textContent = text; el("message").classList.toggle("error", error); }
  function changed() {
    if (embedded) window.parent.postMessage({ type:"qq-account-changed" }, location.origin);
    if (window.opener) { try { window.opener.postMessage({ type:"qq-account-changed" }, location.origin); } catch {} }
  }
  function draw() {
    el("providers").hidden = !!snapshot?.authenticated;
    el("registration").hidden = !snapshot?.needsUsername;
    el("signed-in").hidden = !snapshot?.authenticated || snapshot.needsUsername;
    el("logout").hidden = !snapshot?.authenticated;
    el("username-display").textContent = snapshot?.user?.username || "";
    el("developer-access").textContent = t.developerAccess;
    el("developer-access").hidden = !snapshot?.canDeveloper;
    for (const id of ["google", "github"]) {
      const enabled = !!snapshot?.available && snapshot.providers.some(provider => provider.id === id && provider.enabled);
      el(id).setAttribute("aria-disabled", String(!enabled));
      if (enabled) el(id).href = `/auth/${id}/start?lang=${language}`;
      else el(id).removeAttribute("href");
    }
    el("register").disabled = busy;
    el("logout").disabled = busy;
    el("refresh").disabled = busy;
  }
  async function refresh() {
    const serial = ++refreshSerial;
    notice(t.loading);
    try {
      const response = await fetch("/api/account", { credentials:"same-origin", cache:"no-store", signal:AbortSignal.timeout(8000) });
      const value = await response.json();
      if (serial !== refreshSerial) return;
      snapshot = value;
      draw();
      notice(!response.ok ? t.unavailable : !snapshot.available ? t.setup : snapshot.needsUsername ? t.pending : snapshot.authenticated ? t.signedIn : t.guest, !response.ok);
      changed();
    } catch { if (serial === refreshSerial) notice(t.unavailable, true); }
  }
  async function mutate(route, body) {
    if (busy || !snapshot?.csrfToken) return;
    busy = true; draw();
    refreshSerial++;
    try {
      const response = await fetch(route, { method:"POST", credentials:"same-origin", cache:"no-store", signal:AbortSignal.timeout(10000),
        headers:{ "Content-Type":"application/json", "X-CSRF-Token":snapshot.csrfToken }, body:JSON.stringify(body) });
      const data = await response.json();
      if (!response.ok) { notice(t[data.error] || t.unavailable, true); return; }
      snapshot = data;
      draw(); changed();
      notice(route.endsWith("logout") ? t.loggedOut : t.complete);
    } catch { notice(t.unavailable, true); }
    finally { busy = false; draw(); }
  }
  el("registration").addEventListener("submit", event => { event.preventDefault(); mutate("/api/account/username", { username:el("username").value }); });
  el("logout").addEventListener("click", () => {
    if (embedded && window.parent.qqCloud) window.parent.qqCloud.action({ id:"logout" });
    else mutate("/api/account/logout", {});
  });
  el("refresh").addEventListener("click", refresh);
  el("return").addEventListener("click", () => {
    changed();
    if (embedded) { window.parent.postMessage({ type:"qq-service-close" }, location.origin); return; }
    if (window.opener || sessionStorage.getItem("qq-account-popup") === "1") {
      try { window.opener?.focus(); } catch {}
      window.close();
    }
    else location.assign("/");
  });
  for (const id of ["google", "github"]) el(id).addEventListener("click", event => {
    if (el(id).getAttribute("aria-disabled") === "true") event.preventDefault();
    else if (embedded) {
      event.preventDefault();
      if (!window.parent.qqAccount?.oauth(id, language)) notice(language === "ja" ? "認証画面のポップアップを許可してください。" : "Allow the authentication pop-up.", true);
    }
  });
  const tx = (ja, en) => language === "ja" ? ja : en;
  function cloud(data) {
    el("cloud-panel").hidden = false;
    el("cloud-title").textContent = tx("クラウド保存", "Cloud Save");
    el("return").disabled = !!data.blocked;
    const states = {
      starting:tx("進行データを準備しています。", "Preparing progress data."), guest:tx("ゲストの進行は、この端末にのみ保存されます。", "Guest progress is saved only on this device."),
      loading:tx("アカウントの保存データを確認中です。", "Checking account saves."), ready: data.dirty ? tx("端末に保存済み・クラウドへ送信待ち", "Saved locally; upload pending") : tx("クラウドと同期済み", "Cloud save synchronized"),
      offline:tx("接続できないため、このアカウントの端末内データに保存しています。他の端末に切り替える前に再同期してください。", "Offline. Changes stay in this account's local cache. Sync before switching devices."),
      import_choice:tx("初回の保存です。この端末のゲスト進行を引き継ぐか、新しく始めるか選んでください。合算はしません。", "First cloud save. Move this device's guest progress, or start fresh. Progress is never added together."),
      guest_choice:tx("クラウドとゲストの両方にデータがあります。クラウドを使うか、ゲスト進行で置き換えるか選んでください。両方をバックアップします。", "Both cloud and guest progress exist. Use the cloud save, or replace it with guest progress. Backups are retained."),
      conflict:tx("別の保存と競合しています。自動上書きはしません。比較して、残すデータを選んでください。", "Conflicting saves detected. Nothing is automatically overwritten. Choose which progress to keep."),
      device_busy:tx("別の端末・タブが操作中か、操作権が切れました。こちらで再開すると、前の端末は更新できなくなります。", "Another device/tab is active, or this device lost its lease. Taking over prevents the old device from saving."),
      load_error:tx("クラウドを確認できません。既存のデータは上書きしていません。再試行するか、ログアウトしてゲストで遊べます。", "Cloud saves are unavailable; existing data is untouched. Retry, or sign out to play as a guest."),
      local_save_error:tx("端末のバックアップに失敗しました。上書きを停止しています。", "Local backup failed. Replacement was stopped."),
      logout_pending:tx("未送信のデータがあります。再試行するか、この端末に保留したままログアウトできます。別のアカウントには送りません。", "Unsynced changes remain. Retry, or sign out while retaining them on this device. They will not upload to another account."),
    };
    el("cloud-status").textContent = states[data.state] || data.state;
    if (data.error === "logout_unavailable") el("cloud-status").textContent = tx("ログアウトを完了できませんでした。アカウントは切り替えていません。接続を確認して、もう一度ログアウトしてください。", "Sign-out did not complete; the active account is unchanged. Check the connection and try signing out again.");
    if (["save_too_large", "save_too_complex"].includes(data.error)) el("cloud-status").textContent = tx("同期できるデータ量の上限に達しました。進行はこの端末に保持されています。", "The cloud-save size limit was reached. Progress is retained on this device.");
    el("cloud-meta").textContent = data.profile === "guest" ? "" : `${tx("保存世代", "Revision")} ${data.revision}${data.updated_at ? " / " + new Date(data.updated_at).toLocaleString(language === "ja" ? "ja-JP" : "en-US") : ""}`;
    el("cloud-policy").textContent = tx("ログアウト後はゲストへ戻ります。引き継ぎ済みのゲストは新規状態になります。音量・解像度は端末ごと。戦闘途中の通常ランは戦闘開始前から再開し、進行中のWeb対戦の端末移動には対応しません。認証だけ外部画面を使用します。", "Signing out returns to guest progress; an imported guest starts fresh. Audio/display preferences are per-device. Normal battles resume from their pre-battle checkpoint. Live multiplayer cannot move between devices. Only provider authentication uses an external window.");
    el("cloud-comparison").replaceChildren();
    if (["import_choice", "guest_choice", "conflict"].includes(data.state)) for (const [key, label] of [["cloud", tx("クラウド", "Cloud")], ["local", tx("このアカウントの端末内データ", "Local account cache")], ["guest", tx("この端末のゲスト", "Device guest")]]) {
      const box = document.createElement("div"), info = data[key] || {};
      const heading = document.createElement("strong"); heading.textContent = label;
      const text = document.createElement("p"); text.textContent = `${tx("メタポイント", "Meta Points")}: ${info.points || 0} / ${tx("解放", "Unlocks")}: ${info.unlocks || 0} / ${tx("途中ラン", "Saved Runs")}: ${info.runs || 0}`;
      box.append(heading, text); el("cloud-comparison").append(box);
    }
    el("cloud-actions").replaceChildren();
    function button(id, ja, en, confirmation = "", extra = {}) {
      const node = document.createElement("button"); node.type = "button"; node.textContent = tx(ja, en); node.dataset.cloudAction = id; node.disabled = !!data.busy;
      node.addEventListener("click", () => { if (confirmation && !window.confirm(confirmation)) return; window.parent.qqCloud.action({ id, ...extra }); });
      el("cloud-actions").append(node);
    }
    const replace = tx("現在の進行を置き換えます。置き換え前のデータはバックアップに保存します。よろしいですか？", "Replace current progress? A backup will be retained. Continue?");
    if (data.state === "import_choice") { button("import", "ゲストの進行を引き継ぐ", "Move guest progress"); button("new", "新しく始める", "Start fresh"); }
    if (data.state === "guest_choice") { button("cloud", "クラウドを使う", "Use cloud save"); button("import", "ゲストの進行に置き換える", "Replace with guest save", replace); }
    if (data.state === "conflict") { button("cloud", "クラウドを使う", "Use cloud save", replace); button("local", "端末内の進行を使う", "Use local progress", replace); }
    if (data.state === "device_busy") button("takeover", "この端末で再開", "Continue on this device");
    if (["load_error", "local_save_error", "logout_pending"].includes(data.state)) button("retry", "再試行", "Retry");
    if (data.state === "logout_pending") button("logout_anyway", "端末に保留してログアウト", "Keep locally and sign out");
    if (["ready", "offline"].includes(data.state)) { button("sync", "今すぐ同期", "Sync now"); button("history", "保存履歴", "Save history"); }
    el("cloud-history").replaceChildren();
    if (data.state === "ready") for (const record of data.history || []) {
      const row = document.createElement("p"), text = document.createElement("span"), restore = document.createElement("button");
      text.textContent = `#${record.revision} ${new Date(record.updated_at).toLocaleString(language === "ja" ? "ja-JP" : "en-US")} `;
      restore.className = "secondary"; restore.textContent = tx("復元", "Restore"); restore.disabled = !!data.busy;
      restore.addEventListener("click", () => { if (window.confirm(replace)) window.parent.qqCloud.action({ id:"restore", revision:record.revision }); });
      row.append(text, restore); el("cloud-history").append(row);
    }
    if (data.state === "ready" && data.history?.length >= 0) for (const filename of data.local_backups || []) {
      const row = document.createElement("p"), text = document.createElement("span"), restore = document.createElement("button");
      const stamp = Number(filename.match(/-(\d+)\.json$/)?.[1]);
      text.textContent = tx("端末の退避データ ", "Local backup ") + (stamp ? new Date(stamp / 1000).toLocaleString(language === "ja" ? "ja-JP" : "en-US") : "") + " ";
      restore.className = "secondary"; restore.textContent = tx("復元", "Restore"); restore.disabled = !!data.busy;
      restore.addEventListener("click", () => { if (window.confirm(replace)) window.parent.qqCloud.action({ id:"restore_local", filename }); });
      row.append(text, restore); el("cloud-history").append(row);
    }
  }
  window.addEventListener("message", event => {
    if (!embedded || event.source !== window.parent || event.origin !== location.origin) return;
    if (event.data?.type === "qq-cloud-state") cloud(event.data.data);
    if (["qq-service-refresh", "qq-profile-changed"].includes(event.data?.type)) refresh();
  });
  if (embedded) document.querySelector(".brand").addEventListener("click", event => { event.preventDefault(); window.parent.postMessage({ type:"qq-service-close" }, location.origin); });
  document.addEventListener("keydown", event => { if (embedded && event.key === "Escape") window.parent.postMessage({type:"qq-service-close"},location.origin); });
  refresh().then(() => {
    const error = new URLSearchParams(location.search).get("error");
    if (error && t[error]) notice(t[error], true);
    history.replaceState(null, "", `/account?lang=${language}`);
  });
})();
