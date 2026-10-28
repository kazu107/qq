"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { randomBytes, createHash, createHmac, timingSafeEqual } = require("node:crypto");
const { isIP } = require("node:net");
const { AccountStore } = require("./store");
const { OAuthProviders } = require("./oauth");

const SESSION_SECONDS = 14 * 86400;
const ATTEMPT_SECONDS = 600;
const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const PROVIDERS = ["google", "github"];
const RESERVED = new Set(["admin", "administrator", "root", "system", "support", "moderator", "queuequest", "管理者", "運営", "公式"]);
const FILES = new Map([
  ["/account", ["index.html", "text/html; charset=utf-8"]],
  ["/account/", ["index.html", "text/html; charset=utf-8"]],
  ["/account/app.js", ["app.js", "text/javascript; charset=utf-8"]],
  ["/account/client.js", ["client.js", "text/javascript; charset=utf-8"]],
  ["/account/services.js", ["services.js", "text/javascript; charset=utf-8"]],
  ["/account/style.css", ["style.css", "text/css; charset=utf-8"]],
  ["/account/smooth-scroll.js", ["smooth-scroll.js", "text/javascript; charset=utf-8"]],
  ["/account/google-g.png", ["google-g.png", "image/png"]],
  ["/account/GoogleSans-Medium.ttf", ["GoogleSans-Medium.ttf", "font/ttf"]],
  ["/account/GoogleSans-OFL.txt", ["GoogleSans-OFL.txt", "text/plain; charset=utf-8"]],
]);
for (const orientation of ["v", "h"]) {
  for (const state of ["track", "grabber", "highlight", "pressed"]) {
    const file = `scrollbar_${orientation}_${state}.png`;
    FILES.set(`/account/scrollbars/${file}`, [`scrollbars/${file}`, "image/png"]);
  }
}

function hash(value) { return createHash("sha256").update(value).digest("hex"); }
function token() { return randomBytes(32).toString("base64url"); }
function csrf(session) { return createHmac("sha256", session).update("qq-account-csrf-v1").digest("base64url"); }
function equal(a, b) {
  return typeof a === "string" && typeof b === "string" && TOKEN.test(a) && TOKEN.test(b) && timingSafeEqual(Buffer.from(a), Buffer.from(b));
}
function cookie(request, name) {
  const header = request.headers.cookie || "";
  if (header.length > 8192) return "";
  const matches = header.split(";").map(item => item.trim()).filter(item => item.startsWith(name + "="));
  if (matches.length !== 1) return "";
  const value = matches[0].slice(name.length + 1);
  return TOKEN.test(value) ? value : "";
}
function setCookie(response, name, value, seconds, secure) {
  const cookies = response.getHeader("Set-Cookie") || [];
  response.setHeader("Set-Cookie", [...cookies, `${name}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${seconds}${secure ? "; Secure" : ""}`]);
}
function json(response, status, value) {
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(value));
}
function redirect(response, location) {
  response.writeHead(303, { Location: location });
  response.end();
}
function originOf(value) {
  try {
    const url = new URL(value);
    const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (url.username || url.password || url.pathname !== "/" || url.search || url.hash ||
      (url.protocol !== "https:" && !(url.protocol === "http:" && local))) return null;
    return url;
  } catch { return null; }
}
function validateUsername(value) {
  if (typeof value !== "string" || value.length > 200) return null;
  const username = value.normalize("NFKC").trim();
  const count = Array.from(username).length;
  const key = username.toLowerCase();
  if (count < 3 || count > 20 || !/^[\p{L}\p{N}_-]+$/u.test(username) || RESERVED.has(key)) return null;
  return { username, key };
}
async function readJson(request) {
  if (request.headers["content-type"]?.split(";")[0].trim() !== "application/json") throw Object.assign(new Error(), { code: "invalid_json" });
  const chunks = [];
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > 4096) throw Object.assign(new Error(), { code: "body_too_large" });
    chunks.push(chunk);
  }
  try {
    const data = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error();
    return data;
  } catch { throw Object.assign(new Error(), { code: "invalid_json" }); }
}

function createAccountService(env = process.env, options = {}) {
  const enabled = options.enabled ?? env.AUTH_ENABLED === "true";
  let store = options.store;
  let oauth = options.oauth;
  let initializationFailed = false;
  const limits = new Map();
  let closePromise;
  function configuration() {
    const origin = originOf(options.getOrigin ? options.getOrigin() : env.PUBLIC_ORIGIN);
    if (!enabled || !origin || (env.NODE_ENV === "production" && origin.protocol !== "https:")) return null;
    if (initializationFailed) return null;
    try {
      if (!store && env.DATABASE_URL) store = new AccountStore(env);
      if (!oauth) oauth = new OAuthProviders(env);
    } catch {
      initializationFailed = true;
      return null;
    }
    if (!store || !PROVIDERS.some(provider => oauth.enabled(provider))) return null;
    const secure = origin.protocol === "https:";
    return { origin, secure, sessionCookie: secure ? "__Host-qq-session" : "qq-session-dev", bindingCookie: secure ? "__Host-qq-oauth" : "qq-oauth-dev" };
  }
  function ipOf(request) {
    if (env.TRUST_PROXY === "1") {
      const forwarded = request.headers["x-forwarded-for"];
      if (typeof forwarded === "string" && forwarded.length < 512) {
        const ip = forwarded.split(",").at(-1).trim();
        if (isIP(ip)) return ip;
      }
    }
    return request.socket.remoteAddress || "unknown";
  }
  function limited(key, maximum, duration) {
    const now = Date.now();
    for (const [name, value] of limits) if (value.until <= now) limits.delete(name);
    if (!limits.has(key)) {
      if (limits.size >= 5000) return true;
      limits.set(key, { count: 0, until: now + duration });
    }
    return ++limits.get(key).count > maximum;
  }
  function profile(config, user = null, session = "", reason = "") {
    const allowedNames = String(env.DEVELOPER_USERNAMES || "").split(",").map(value => value.normalize("NFKC").trim().toLowerCase()).filter(Boolean);
    const allowedIds = String(env.DEVELOPER_USER_IDS || "").split(",").map(value => value.trim()).filter(Boolean);
    return { available: !!config, authenticated: !!user, needsUsername: !!user && !user.username, user,
      canDeveloper: !!user?.username && (allowedNames.includes(user.username.toLowerCase()) || allowedIds.includes(user.id)),
      csrfToken: user ? csrf(session) : null, reason,
      providers: PROVIDERS.map(id => ({ id, enabled: !!config && oauth.enabled(id) })) };
  }
  async function handle(request, response) {
    if (!request.url.startsWith("/") || request.url.startsWith("//")) {
      json(response, 400, { error: "invalid_request_target" }); return true;
    }
    const url = new URL(request.url, "http://internal");
    const route = /^\/auth\/(google|github)\/(start|callback)$/.exec(url.pathname);
    if (!FILES.has(url.pathname) && url.pathname !== "/api/account" && !url.pathname.startsWith("/api/account/") && !route) return false;
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("Referrer-Policy", "no-referrer");
    response.setHeader("Cross-Origin-Resource-Policy", "same-origin");
    response.setHeader("Vary", "Cookie");
    if (FILES.has(url.pathname)) {
      if (!["GET", "HEAD"].includes(request.method)) { json(response, 405, { error: "method_not_allowed" }); return true; }
      const [file, mime] = FILES.get(url.pathname);
      response.setHeader("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'self'; form-action 'self'");
      response.setHeader("X-Frame-Options", "SAMEORIGIN");
      response.setHeader("Content-Type", mime);
      response.end(request.method === "HEAD" ? undefined : fs.readFileSync(path.join(__dirname, "public", file)));
      return true;
    }
    const config = configuration();
    if (!config) {
      json(response, url.pathname === "/api/account" ? 200 : 503, url.pathname === "/api/account" ? profile(null, null, "", "not_configured") : { error: "auth_not_configured" });
      return true;
    }
    try {
      await store.ready();
      if (route) {
        if (request.method !== "GET") { json(response, 405, { error: "method_not_allowed" }); return true; }
        const [, provider, action] = route;
        if (!oauth.enabled(provider)) { redirect(response, "/account?error=provider_unavailable"); return true; }
        if (limited(`oauth:${ipOf(request)}`, 40, ATTEMPT_SECONDS * 1000)) {
          response.setHeader("Retry-After", "600"); json(response, 429, { error: "rate_limited" }); return true;
        }
        if (action === "start") {
          const state = token(), binding = token(), verifier = token(), nonce = token();
          const language = url.searchParams.get("lang") === "en" ? "en" : "ja";
          const destination = await oauth.authorizationUrl(provider, { state, verifier, nonce, redirectUri: `${config.origin.origin}/auth/${provider}/callback` });
          await store.saveAttempt({ stateHash: hash(state), bindingHash: hash(binding), provider, verifier, nonce, language, expiresAt: new Date(Date.now() + ATTEMPT_SECONDS * 1000) });
          setCookie(response, config.bindingCookie, binding, ATTEMPT_SECONDS, config.secure);
          redirect(response, destination);
        } else {
          const state = url.searchParams.get("state") || "", binding = cookie(request, config.bindingCookie);
          if (!TOKEN.test(state) || !binding || url.searchParams.getAll("state").length !== 1 || url.searchParams.getAll("code").length > 1 || url.searchParams.getAll("error").length > 1) {
            redirect(response, "/account?error=invalid_login"); return true;
          }
          const attempt = await store.consumeAttempt(hash(state), hash(binding), provider);
          if (!attempt) { redirect(response, "/account?error=invalid_login"); return true; }
          setCookie(response, config.bindingCookie, "", 0, config.secure);
          if (url.searchParams.has("error")) { redirect(response, `/account?lang=${attempt.language}&error=cancelled`); return true; }
          const code = url.searchParams.get("code");
          if (!code || code.length > 2048) { redirect(response, "/account?error=invalid_login"); return true; }
          const currentUrl = new URL(url.pathname + url.search, config.origin);
          const subject = await oauth.identity(provider, currentUrl, attempt);
          if (typeof subject !== "string" || !subject || subject.length > 255) throw new Error("invalid_subject");
          const user = await store.getOrCreateUser(provider, subject);
          const session = token();
          await store.createSession(hash(session), user.id, new Date(Date.now() + SESSION_SECONDS * 1000));
          const previous = cookie(request, config.sessionCookie);
          if (previous) await store.deleteSession(hash(previous));
          setCookie(response, config.sessionCookie, session, SESSION_SECONDS, config.secure);
          redirect(response, `/account?lang=${attempt.language}&result=authenticated`);
        }
        store.cleanup().catch(() => {});
        return true;
      }
      const session = cookie(request, config.sessionCookie);
      const user = session ? await store.getSession(hash(session)) : null;
      if (url.pathname === "/api/account") {
        json(response, request.method === "GET" ? 200 : 405, request.method === "GET" ? profile(config, user, session) : { error: "method_not_allowed" });
        return true;
      }
      if (!["/api/account/username", "/api/account/logout"].includes(url.pathname)) { json(response, 404, { error: "not_found" }); return true; }
      if (request.method !== "POST") { json(response, 405, { error: "method_not_allowed" }); return true; }
      if (!user) { json(response, 401, { error: "login_required" }); return true; }
      if (request.headers.origin !== config.origin.origin || request.headers["sec-fetch-site"] === "cross-site" || !equal(request.headers["x-csrf-token"], csrf(session))) {
        json(response, 403, { error: "invalid_csrf" }); return true;
      }
      if (limited(`write:${hash(session)}`, 30, 60000)) { response.setHeader("Retry-After", "60"); json(response, 429, { error: "rate_limited" }); return true; }
      if (url.pathname === "/api/account/logout") {
        if (request.headers["x-qq-account"] && request.headers["x-qq-account"] !== user.id) { json(response, 409, { error: "account_changed" }); return true; }
        await store.deleteSession(hash(session));
        setCookie(response, config.sessionCookie, "", 0, config.secure);
        json(response, 200, profile(config));
        return true;
      }
      const body = await readJson(request);
      if (user.username) { json(response, 409, { error: "username_already_set" }); return true; }
      const name = validateUsername(body.username);
      if (!name) { json(response, 400, { error: "invalid_username" }); return true; }
      const result = await store.setUsername(user.id, name.username, name.key);
      if (result.error) { json(response, 409, result); return true; }
      json(response, 200, profile(config, result.user, session));
      return true;
    } catch (error) {
      if (route) redirect(response, "/account?error=login_failed");
      else if (["invalid_json", "body_too_large"].includes(error.code)) json(response, error.code === "body_too_large" ? 413 : 400, { error: error.code });
      else json(response, 503, { ...profile(null, null, "", "temporarily_unavailable"), error: "temporarily_unavailable" });
      return true;
    }
  }
  return { handle,
    async storage() {
      if (!configuration()) throw Object.assign(new Error(), { status: 503, code: "accounts_unavailable" });
      await store.ready(); return store;
    },
    async authorize(request, write = false) {
      const config = configuration();
      if (!config) throw Object.assign(new Error(), { status: 503, code: "accounts_unavailable" });
      await store.ready();
      const session = cookie(request, config.sessionCookie);
      const user = session ? await store.getSession(hash(session)) : null;
      if (!user?.username) throw Object.assign(new Error(), { status: 401, code: "login_required" });
      if (write && (request.headers.origin !== config.origin.origin || request.headers["sec-fetch-site"] === "cross-site" || !equal(request.headers["x-csrf-token"], csrf(session)))) {
        throw Object.assign(new Error(), { status: 403, code: "invalid_csrf" });
      }
      return user;
    }, close() {
    if (!closePromise) closePromise = Promise.resolve(store?.close());
    return closePromise;
  } };
}

module.exports = { createAccountService, validateUsername, hash, csrf, originOf, SESSION_SECONDS, ATTEMPT_SECONDS };
