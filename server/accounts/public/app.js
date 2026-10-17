"use strict";

(() => {
  const language = new URLSearchParams(location.search).get("lang") === "en" ? "en" : "ja";
  if (window.opener) sessionStorage.setItem("qq-account-popup", "1");
  const messages = {
    ja: { title:"アカウント", subtitle:"Google・GitHubでログイン／新規登録します。", google:"Googleで続ける", github:"GitHubで続ける",
      loading:"アカウントを確認中...", guest:"ログイン方法を選んでください。", setup:"ログイン機能は準備中です。ゲームはログインなしで引き続き遊べます。",
      pending:"本人確認が完了しました。ユーザー名を決めて登録してください。", signedIn:"ログインしています。", username:"ユーザー名", register:"登録を完了", identity:"登録済みユーザー名",
      hint:"3〜20文字。日本語・英数字・ハイフン・アンダースコアを使えます。大文字小文字や全角半角の違いだけの名前は重複扱いになります。登録後の変更には対応していません。",
      providerNote:"初回はユーザー名を設定します。GoogleとGitHubは別々のアカウントです。同じメールアドレスでも自動で統合しません。",
      local:"現在のラン・メタ進行はこの端末／ブラウザに保存されます。ログインによるクラウド同期やランキング投稿はまだ行いません。",
      privacy:"保存するのはログイン方法の固定IDとユーザー名です。パスワード・メールアドレス・外部サービスのアクセストークンは保存しません。",
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
      local:"Runs and Meta Progress stay on this device/browser. Sign-in does not yet sync saves or submit leaderboard scores.",
      privacy:"Only the provider's stable user ID and your username are stored. No passwords, email addresses or provider access tokens are stored.",
      logout:"Sign out", refresh:"Check again", back:"Return to game", complete:"Registration complete. You can return to the game.", loggedOut:"You have signed out.",
      invalid_username:"Use 3-20 letters/numbers, hyphens or underscores. Reserved names are unavailable.", username_taken:"That username is already taken. Please choose another.", username_already_set:"Your username is already registered. Check your account again.",
      login_required:"Your session expired. Please sign in again.", cancelled:"Sign-in cancelled.", invalid_login:"This sign-in expired or started in another browser. Please start again.", login_failed:"Sign-in failed. Please try again later.",
      provider_unavailable:"This sign-in method is unavailable.", rate_limited:"Too many attempts. Please wait and try again.", unavailable:"Accounts are temporarily unavailable. Local play is unaffected.", invalid_csrf:"Reload this page and try again." },
  };
  const t = messages[language];
  const el = id => document.getElementById(id);
  let snapshot = null, busy = false;
  document.documentElement.lang = language;
  document.title = `QueueQuest | ${t.title}`;
  for (const [id, value] of Object.entries({ title:t.title, subtitle:t.subtitle, "google-label":t.google, "github-label":t.github,
    "username-label":t.username, "username-hint":t.hint, "provider-note":t.providerNote, "local-save-note":t.local, "privacy-note":t.privacy,
    register:t.register, "identity-label":t.identity, logout:t.logout, refresh:t.refresh, return:t.back })) el(id).textContent = value;
  function notice(text, error = false) { el("message").textContent = text; el("message").classList.toggle("error", error); }
  function changed() {
    if (window.opener) { try { window.opener.postMessage({ type:"qq-account-changed" }, location.origin); } catch {} }
  }
  function draw() {
    el("providers").hidden = !!snapshot?.authenticated;
    el("registration").hidden = !snapshot?.needsUsername;
    el("signed-in").hidden = !snapshot?.authenticated || snapshot.needsUsername;
    el("logout").hidden = !snapshot?.authenticated;
    el("username-display").textContent = snapshot?.user?.username || "";
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
    notice(t.loading);
    try {
      const response = await fetch("/api/account", { credentials:"same-origin", cache:"no-store", signal:AbortSignal.timeout(8000) });
      snapshot = await response.json();
      draw();
      notice(!response.ok ? t.unavailable : !snapshot.available ? t.setup : snapshot.needsUsername ? t.pending : snapshot.authenticated ? t.signedIn : t.guest, !response.ok);
      changed();
    } catch { notice(t.unavailable, true); }
  }
  async function mutate(route, body) {
    if (busy || !snapshot?.csrfToken) return;
    busy = true; draw();
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
  el("logout").addEventListener("click", () => mutate("/api/account/logout", {}));
  el("refresh").addEventListener("click", refresh);
  el("return").addEventListener("click", () => {
    changed();
    if (window.opener || sessionStorage.getItem("qq-account-popup") === "1") {
      try { window.opener?.focus(); } catch {}
      window.close();
    }
    else location.assign("/");
  });
  for (const id of ["google", "github"]) el(id).addEventListener("click", event => {
    if (el(id).getAttribute("aria-disabled") === "true") event.preventDefault();
  });
  refresh().then(() => {
    const error = new URLSearchParams(location.search).get("error");
    if (error && t[error]) notice(t[error], true);
    history.replaceState(null, "", `/account?lang=${language}`);
  });
})();
