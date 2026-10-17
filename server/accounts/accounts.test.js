"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { randomBytes } = require("node:crypto");
const { validateUsername, originOf, hash, csrf } = require("./http");
const { poolOptions } = require("./store");
const { main: migrate } = require("./migrate");
const { testDatabaseEnv, accountFixture, BrowserSession, listen, close } = require("../../tests/helpers/account_fixture");
const { createQqServer } = require("../server");

test("Unicode usernames are normalized, bounded and safe", () => {
  assert.deepEqual(validateUsername(" Ｑｕｅｕｅ＿冒険者 "), { username: "Queue_冒険者", key: "queue_冒険者" });
  for (const input of [null, 2, "ab", "a".repeat(21), "admin", "ＡＤＭＩＮ", "管理者", "a b", "a/b", "<script>", "a\u202eb", "a\u0000b", "hello😀"]) {
    assert.equal(validateUsername(input), null, JSON.stringify(input));
  }
  assert(validateUsername("勇者テスト"));
});

test("public origin and database TLS do not trust unverified remote hosts", () => {
  assert.equal(originOf("https://game.example/path"), null);
  assert.equal(originOf("http://game.example"), null);
  assert.equal(originOf("https://user:pass@game.example"), null);
  assert.equal(originOf("http://localhost:3000").origin, "http://localhost:3000");
  const remote = poolOptions({ DATABASE_URL: "postgres://user:pass@db.example/game?sslmode=no-verify" });
  assert.equal(remote.ssl.rejectUnauthorized, true);
  assert(!remote.connectionString.includes("sslmode"));
  const { Client } = require("pg");
  const bypass = new Client(poolOptions({ DATABASE_URL: "postgres://user:pass@db.example/game?ssl=0&sslmode=disable&host=localhost" }));
  assert.equal(bypass.connectionParameters.ssl.rejectUnauthorized, true);
  assert.equal(bypass.connectionParameters.host, "db.example");
  assert.equal(poolOptions({ DATABASE_URL: "postgres://user:pass@localhost/game" }).ssl, false);
  assert.equal(poolOptions({ NODE_ENV: "production", DATABASE_URL: "postgres://user:pass@localhost/game" }).ssl.rejectUnauthorized, true);
  assert.throws(() => poolOptions({ DATABASE_URL: "postgres://db.example/game", AUTH_DATABASE_CA_BASE64: "bad" }));
});

test("disabled login preserves static game and requires no database or OAuth secrets", async () => {
  await migrate({});
  const { server } = createQqServer({ env: {} });
  const origin = await listen(server);
  try {
    const response = await fetch(`${origin}/api/account`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    const data = await response.json();
    assert.equal(data.available, false);
    assert.equal(data.authenticated, false);
    assert(data.providers.every(item => !item.enabled));
    assert.equal((await fetch(`${origin}/auth/google/start`)).status, 503);
    const page = await fetch(`${origin}/account`);
    assert.equal(page.status, 200);
    assert(page.headers.get("content-security-policy").includes("frame-ancestors 'none'"));
    assert.equal((await fetch(`${origin}/account/client.js`)).status, 200);
    assert.equal((await fetch(`${origin}/health`)).status, 200);
    assert.equal((await fetch(`${origin}/`)).status, 200);
  } finally { await close(server); }
});

test("real PostgreSQL + code/PKCE/OIDC integration", { skip: !testDatabaseEnv() && "Set QQ_AUTH_TEST_DATABASE_URL to a disposable loopback qq_auth_tests database" }, async t => {
  const fixture = await accountFixture();
  const { store, mock, origin } = fixture;
  const session = () => new BrowserSession(origin);
  try {
    await t.test("additive migrations are repeatable; concurrent identities are stable and provider-scoped", async () => {
      await store.migrate();
      const users = await Promise.all(Array.from({ length: 8 }, () => store.getOrCreateUser("google", "concurrent")));
      assert.equal(new Set(users.map(item => item.id)).size, 1);
      const other = await store.getOrCreateUser("github", "concurrent");
      assert.notEqual(other.id, users[0].id);
      await store.migrate();
      assert.equal((await store.getOrCreateUser("google", "concurrent")).id, users[0].id);
    });
    await t.test("first registration, CSRF rejection, Japanese username, logout and returning login", async () => {
      const browser = session();
      const { start, result } = await browser.login();
      assert.equal(result.status, 303);
      assert(result.headers.get("location").includes("authenticated"));
      assert(start.headers.get("set-cookie").includes("HttpOnly; SameSite=Lax"));
      const profile = await browser.profile();
      assert.equal(profile.needsUsername, true);
      assert(profile.user.id);
      const badOrigin = await browser.write("/api/account/username", { username: "勇者テスト" }, { Origin: "https://attacker.invalid" });
      assert.equal(badOrigin.status, 403);
      assert.equal((await browser.write("/api/account/username", { username: "勇者テスト" }, { "X-CSRF-Token": "x".repeat(43) })).status, 403);
      assert.equal((await browser.write("/api/account/username", { username: "勇者テスト" }, { "Sec-Fetch-Site": "cross-site" })).status, 403);
      assert.equal((await browser.write("/api/account/username", { username: "<script>" })).status, 400);
      const registered = await (await browser.write("/api/account/username", { username: "勇者テスト" })).json();
      assert.equal(registered.user.username, "勇者テスト");
      assert.equal(registered.needsUsername, false);
      assert.equal((await browser.write("/api/account/username", { username: "別のユーザー" })).status, 409);
      const oldCookie = browser.cookies.get("qq-session-dev");
      assert.equal((await browser.write("/api/account/logout")).status, 200);
      assert.equal((await browser.profile()).authenticated, false);
      assert.equal(await store.getSession(hash(oldCookie)), null);
      await browser.login();
      const returning = await browser.profile();
      assert.equal(returning.user.id, profile.user.id);
      assert.equal(returning.user.username, "勇者テスト");
      assert.equal(returning.needsUsername, false);
      const tables = await store.pool.query("SELECT table_name, column_name FROM information_schema.columns WHERE table_name LIKE 'qq_accounts_%'");
      assert(!tables.rows.some(row => /email|access_token|password|refresh_token/.test(row.column_name)));
    });
    await t.test("GitHub immutable identity, no automatic cross-provider linking, unique normalized names", async () => {
      const browser = session();
      const { result } = await browser.login("github");
      assert(result.headers.get("location").includes("authenticated"));
      assert.equal((await browser.profile()).needsUsername, true);
      const taken = await browser.write("/api/account/username", { username: "勇者テスト" });
      assert.equal(taken.status, 409);
      assert.equal((await taken.json()).error, "username_taken");
      await browser.write("/api/account/username", { username: "Ｇｉｔ＿勇者" });
      assert.equal((await browser.profile()).user.username, "Git_勇者");
      const user1 = await store.getOrCreateUser("google", "name-race-1");
      const user2 = await store.getOrCreateUser("google", "name-race-2");
      const race = await Promise.all([store.setUsername(user1.id, "RaceName", "racename"), store.setUsername(user2.id, "racename", "racename")]);
      assert.equal(race.filter(result => result.error === "username_taken").length, 1);
    });
    await t.test("state is browser-bound, single-use, provider-bound and time-limited", async () => {
      const browser = session();
      const start = await browser.request("/auth/google/start");
      const grant = await fetch(start.headers.get("location"), { redirect: "manual" });
      const callback = new URL(grant.headers.get("location"));
      const path = callback.pathname + callback.search;
      const stranger = session();
      assert((await stranger.request(path)).headers.get("location").includes("invalid_login"));
      assert((await browser.request(path.replace("/google/", "/github/"))).headers.get("location").includes("invalid_login"));
      assert((await browser.request(path + "&state=" + callback.searchParams.get("state"))).headers.get("location").includes("invalid_login"));
      const before = mock.state.tokenRequests;
      assert((await browser.request(path)).headers.get("location").includes("authenticated"));
      assert((await browser.request(path)).headers.get("location").includes("invalid_login"));
      assert.equal(mock.state.tokenRequests, before + 1);
      const expired = await browser.request("/auth/google/start");
      const state = new URL(expired.headers.get("location")).searchParams.get("state");
      await store.pool.query("UPDATE qq_accounts_oauth_attempts SET expires_at=now()-interval '1 second' WHERE state_hash=$1", [hash(state)]);
      assert((await browser.request(`/auth/google/callback?state=${state}&code=expired`)).headers.get("location").includes("invalid_login"));
    });
    await t.test("OIDC rejects tampered signatures, nonce, audience, issuer and expired tokens", async () => {
      for (const fault of ["signature", "nonce", "audience", "issuer", "expired"]) {
        mock.state.fault = fault;
        const browser = session();
        const { result } = await browser.login();
        assert(result.headers.get("location").includes("login_failed"), fault);
        assert.equal((await browser.profile()).authenticated, false, fault);
      }
      mock.state.fault = "";
    });
    await t.test("PKCE verifier is checked by token endpoint; cancelled grants do not create sessions", async () => {
      const browser = session();
      const start = await browser.request("/auth/google/start");
      const state = new URL(start.headers.get("location")).searchParams.get("state");
      await store.pool.query("UPDATE qq_accounts_oauth_attempts SET verifier=$2 WHERE state_hash=$1", [hash(state), randomBytes(32).toString("base64url")]);
      const grant = await fetch(start.headers.get("location"), { redirect: "manual" });
      const callback = new URL(grant.headers.get("location"));
      assert((await browser.request(callback.pathname + callback.search)).headers.get("location").includes("login_failed"));
      const cancel = await browser.request("/auth/github/start?lang=en");
      const cancelState = new URL(cancel.headers.get("location")).searchParams.get("state");
      assert.equal((await browser.request(`/auth/github/callback?state=${cancelState}&error=access_denied`)).headers.get("location"), "/account?lang=en&error=cancelled");
    });
    await t.test("bounded request bodies, method checks, expiry and session rotation", async () => {
      const browser = session();
      mock.state.googleSubject = "bounds-user";
      await browser.login();
      assert.equal((await browser.request("/api/account", { method: "PUT" })).status, 405);
      assert.equal((await browser.write("/api/account/username", { username: "a".repeat(5000) })).status, 413);
      assert.equal((await browser.write("/api/account/username", { username: "名前テスト" }, { "Content-Type": "text/plain" })).status, 400);
      const previous = browser.cookies.get("qq-session-dev");
      await browser.login();
      assert.notEqual(browser.cookies.get("qq-session-dev"), previous);
      assert.equal(await store.getSession(hash(previous)), null);
      const current = browser.cookies.get("qq-session-dev");
      await store.pool.query("UPDATE qq_accounts_sessions SET expires_at=now()-interval '1 second' WHERE token_hash=$1", [hash(current)]);
      assert.equal((await browser.profile()).authenticated, false);
      assert.equal((await browser.write("/api/account/logout")).status, 401);
    });
    await t.test("database stores only hashed session/callback tokens; sessions survive a new store connection", async () => {
      const browser = session();
      await browser.login("github");
      const raw = browser.cookies.get("qq-session-dev");
      const stored = await store.pool.query("SELECT token_hash FROM qq_accounts_sessions WHERE token_hash=$1", [hash(raw)]);
      assert.equal(stored.rowCount, 1);
      assert.notEqual(stored.rows[0].token_hash, raw);
      assert.equal(csrf(raw).length, 43);
      const { AccountStore } = require("./store");
      const otherStore = new AccountStore(testDatabaseEnv());
      try { assert.equal((await otherStore.getSession(hash(raw))).id, (await browser.profile()).user.id); }
      finally { await otherStore.close(); }
    });
    await t.test("callback attempts are consumed atomically", async () => {
      const stateHash = hash("atomic-state"), bindingHash = hash("atomic-binding");
      await store.saveAttempt({ stateHash, bindingHash, provider: "google", verifier: "v".repeat(43), nonce: "n".repeat(43), language: "ja", expiresAt: new Date(Date.now() + 60000) });
      const results = await Promise.all(Array.from({ length: 8 }, () => store.consumeAttempt(stateHash, bindingHash, "google")));
      assert.equal(results.filter(Boolean).length, 1);
    });
    await t.test("HTTPS uses host-only secure cookies and a fixed callback, never the Host header", async () => {
      const secure = await accountFixture({ reset: false, publicOrigin: "https://game.example" });
      try {
        const browser = new BrowserSession(secure.origin);
        const start = await browser.request("/auth/google/start", { headers: { Host: "attacker.invalid", "X-Forwarded-Host": "attacker.invalid" } });
        const cookie = start.headers.get("set-cookie");
        assert(cookie.startsWith("__Host-qq-oauth="));
        assert(cookie.includes("; Secure") && cookie.includes("; HttpOnly") && cookie.includes("; Path=/"));
        assert(!cookie.includes("Domain="));
        assert.equal(new URL(start.headers.get("location")).searchParams.get("redirect_uri"), "https://game.example/auth/google/callback");
      } finally { await secure.close(); }
    });
    await t.test("OAuth start is rate-limited", async () => {
      const browser = session();
      let response;
      for (let i = 0; i < 41; i++) response = await browser.request("/auth/google/start");
      assert.equal(response.status, 429);
      assert.equal(response.headers.get("retry-after"), "600");
    });
    await t.test("database failure disables accounts without blocking the game, health or static account UI", async () => {
      await store.close();
      store.checkedAt = 0;
      const response = await session().request("/api/account");
      assert.equal(response.status, 503);
      const data = await response.json();
      assert.equal(data.available, false);
      assert.equal(data.reason, "temporarily_unavailable");
      assert.equal((await session().request("/")).status, 200);
      assert.equal((await session().request("/account")).status, 200);
      assert.equal((await session().request("/health")).status, 200);
    });
  } finally { await fixture.close(); }
});
