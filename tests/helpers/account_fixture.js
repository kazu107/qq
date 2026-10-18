"use strict";

const http = require("node:http");
const { once } = require("node:events");
const { generateKeyPairSync, randomBytes, createHash, sign } = require("node:crypto");
const { AccountStore } = require("../../server/accounts/store");
const { OAuthProviders } = require("../../server/accounts/oauth");
const { createQqServer } = require("../../server/server");

function testDatabaseEnv() {
  const connection = process.env.QQ_AUTH_TEST_DATABASE_URL;
  if (!connection) return null;
  const url = new URL(connection);
  // Tests must never truncate an application's actual database.
  if (!["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) || url.pathname !== "/qq_auth_tests") {
    throw new Error("Account tests require a loopback database named qq_auth_tests");
  }
  return { DATABASE_URL: connection, NODE_ENV: "test" };
}

async function listen(server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return `http://127.0.0.1:${server.address().port}`;
}

async function close(server) {
  server.closeAllConnections?.();
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}

async function mockProviders() {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const wrongKey = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
  const jwk = { ...publicKey.export({ format: "jwk" }), kid: "test-signing-key", alg: "RS256", use: "sig" };
  const state = { googleSubject: "google-user-1", githubSubject: 12345, fault: "", tokenRequests: 0, codes: new Map(), access: new Map() };
  let origin;
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, origin);
      const [, provider, action] = url.pathname.split("/");
      response.setHeader("Content-Type", "application/json");
      if (action === "authorize") {
        if (url.searchParams.get("code_challenge_method") !== "S256") throw new Error("pkce_required");
        const code = randomBytes(24).toString("hex");
        state.codes.set(code, { provider, params: url.searchParams, fault: state.fault,
          subject: provider === "google" ? state.googleSubject : state.githubSubject });
        const destination = new URL(url.searchParams.get("redirect_uri"));
        destination.searchParams.set("state", url.searchParams.get("state"));
        destination.searchParams.set("code", code);
        destination.searchParams.set("iss", `${origin}/${provider}`);
        response.writeHead(302, { Location: destination.href }); response.end(); return;
      }
      if (provider === "google" && action === "jwks") { response.end(JSON.stringify({ keys: [jwk] })); return; }
      if (action === "token") {
        state.tokenRequests++;
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        const body = new URLSearchParams(Buffer.concat(chunks).toString());
        const grant = state.codes.get(body.get("code"));
        state.codes.delete(body.get("code"));
        const challenge = createHash("sha256").update(body.get("code_verifier") || "").digest("base64url");
        if (!grant || grant.provider !== provider || grant.params.get("code_challenge") !== challenge ||
          body.get("redirect_uri") !== grant.params.get("redirect_uri")) {
          response.writeHead(400); response.end(JSON.stringify({ error: "invalid_grant" })); return;
        }
        const access = randomBytes(24).toString("hex");
        state.access.set(access, grant.subject);
        const result = { access_token: access, token_type: "Bearer", expires_in: 3600 };
        if (provider === "github") { result.scope = ""; result.token_type = "bearer"; delete result.expires_in; }
        if (provider === "google") {
          const now = Math.floor(Date.now() / 1000);
          const claims = { iss: `${origin}/google`, sub: grant.subject, aud: "google-test-client", iat: now,
            exp: grant.fault === "expired" ? now - 3600 : now + 3600,
            nonce: grant.fault === "nonce" ? "incorrect" : grant.params.get("nonce") };
          if (grant.fault === "audience") claims.aud = "another-client";
          if (grant.fault === "issuer") claims.iss = "https://attacker.invalid";
          const payload = [Buffer.from(JSON.stringify({ alg: "RS256", kid: jwk.kid })).toString("base64url"),
            Buffer.from(JSON.stringify(claims)).toString("base64url")].join(".");
          result.id_token = payload + "." + sign("RSA-SHA256", Buffer.from(payload), grant.fault === "signature" ? wrongKey : privateKey).toString("base64url");
        }
        response.end(JSON.stringify(result)); return;
      }
      if (provider === "github" && action === "user") {
        const id = state.access.get((request.headers.authorization || "").replace("Bearer ", ""));
        if (!id) { response.writeHead(401); response.end("{}"); return; }
        response.end(JSON.stringify({ id, login: "mutable-login", email: "not-stored@example.invalid" })); return;
      }
      response.writeHead(404); response.end("{}");
    } catch { response.writeHead(500); response.end("{}"); }
  });
  origin = await listen(server);
  const servers = Object.fromEntries(["google", "github"].map(provider => [provider, {
    issuer: `${origin}/${provider}`, authorization_endpoint: `${origin}/${provider}/authorize`, token_endpoint: `${origin}/${provider}/token`,
    ...(provider === "google" ? { jwks_uri: `${origin}/google/jwks`, id_token_signing_alg_values_supported: ["RS256"] } : {}),
    code_challenge_methods_supported: ["S256"],
  }]));
  const oauth = new OAuthProviders({ GOOGLE_CLIENT_ID: "google-test-client", GOOGLE_CLIENT_SECRET: "test-only-google-secret",
    GITHUB_CLIENT_ID: "github-test-client", GITHUB_CLIENT_SECRET: "test-only-github-secret" },
  { servers, allowInsecure: true, githubUserEndpoint: `${origin}/github/user` });
  return { state, oauth, origin, close: () => close(server) };
}

async function accountFixture({ reset = true, publicOrigin = "", publicDir, extraEnv = {} } = {}) {
  const databaseEnv = testDatabaseEnv();
  if (!databaseEnv) throw new Error("QQ_AUTH_TEST_DATABASE_URL is required");
  const env = { ...databaseEnv, ...extraEnv };
  const store = new AccountStore(env);
  await store.migrate();
  if (reset) await store.pool.query("TRUNCATE qq_guest_transfers, qq_cloud_save_history, qq_cloud_saves, qq_ranked_commands, qq_ranked_runs, qq_ranked_seasons, qq_accounts_oauth_attempts, qq_accounts_sessions, qq_accounts_identities, qq_accounts_users");
  const mock = await mockProviders();
  let origin;
  const instance = createQqServer({ env, publicDir, account: { enabled: true, store, oauth: mock.oauth, getOrigin: () => publicOrigin || origin } });
  origin = await listen(instance.server);
  return { ...instance, origin, store, mock,
    async close() { await close(instance.server); await store.close(); await mock.close(); } };
}

class BrowserSession {
  constructor(origin) { this.origin = origin; this.cookies = new Map(); }
  async request(path, options = {}) {
    const response = await fetch(new URL(path, this.origin), { ...options, redirect: "manual",
      headers: { Cookie: [...this.cookies].map(([key, value]) => `${key}=${value}`).join("; "), ...options.headers } });
    for (const header of response.headers.getSetCookie()) {
      const [pair] = header.split(";");
      const index = pair.indexOf("=");
      if (header.includes("Max-Age=0;")) this.cookies.delete(pair.slice(0, index));
      else this.cookies.set(pair.slice(0, index), pair.slice(index + 1));
    }
    return response;
  }
  async login(provider = "google") {
    const start = await this.request(`/auth/${provider}/start`);
    const grant = await fetch(start.headers.get("location"), { redirect: "manual" });
    const callback = new URL(grant.headers.get("location"));
    const result = await this.request(callback.pathname + callback.search);
    return { start, grant, callback, result };
  }
  async profile() { return (await this.request("/api/account")).json(); }
  async write(route, body = {}, headers = {}) {
    const profile = await this.profile();
    return this.request(route, { method: "POST", headers: { Origin: this.origin, "Content-Type": "application/json", "X-CSRF-Token": profile.csrfToken || "", ...headers }, body: JSON.stringify(body) });
  }
}

module.exports = { testDatabaseEnv, listen, close, mockProviders, accountFixture, BrowserSession };
