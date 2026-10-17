"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { RankingStore, rules, fail } = require("./store");
const FILES = { "/rankings": ["index.html", "text/html"], "/rankings/": ["index.html", "text/html"], "/rankings/app.js": ["app.js", "text/javascript"], "/rankings/client.js": ["client.js", "text/javascript"] };
const respond = (res, code, value) => { res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" }); res.end(JSON.stringify(value)); };
async function body(req) {
  if (req.headers["content-type"]?.split(";")[0] !== "application/json") fail("invalid_json");
  const chunks = []; let size = 0;
  for await (const chunk of req) { size += chunk.length; if (size > 600000) fail("body_too_large", 413); chunks.push(chunk); }
  try { const value = JSON.parse(Buffer.concat(chunks).toString()); if (!value || typeof value !== "object" || Array.isArray(value)) fail("invalid_json"); return value; }
  catch { fail("invalid_json"); }
}
function createRankingService(account) {
  let store;
  const limits = new Map();
  return { async handle(req, res) {
    const url = new URL(req.url, "http://internal");
    if (!FILES[url.pathname] && !url.pathname.startsWith("/api/ranked")) return false;
    res.setHeader("Cache-Control", "no-store"); res.setHeader("Referrer-Policy", "no-referrer");
    if (FILES[url.pathname]) {
      if (!["GET", "HEAD"].includes(req.method)) { respond(res, 405, { error: "method_not_allowed" }); return true; }
      const [file, type] = FILES[url.pathname];
      res.setHeader("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'");
      res.setHeader("Content-Type", type + "; charset=utf-8");
      res.end(req.method === "HEAD" ? undefined : fs.readFileSync(path.join(__dirname, "public", file))); return true;
    }
    try {
      const database = await account.storage();
      if (!store) store = new RankingStore(database.pool);
      const season = await store.ensureSeason();
      if (req.method === "GET" && url.pathname === "/api/ranked/board") {
        let user = null; try { user = await account.authorize(req); } catch {}
        const selected = url.searchParams.get("season") || season.id;
        const seasons = await database.pool.query("SELECT id,ruleset,starts_at,ends_at FROM qq_ranked_seasons ORDER BY starts_at DESC LIMIT 24");
        respond(res, 200, { season, seasons: seasons.rows, rules, catalog: require("./catalog.json"), ...await store.board(selected, url.searchParams.get("starter") || "", user?.id, Number(url.searchParams.get("page")) || 0) });
      } else if (req.method === "GET" && url.pathname === "/api/ranked/history") {
        const user = await account.authorize(req); respond(res, 200, { runs: await store.history(user.id) });
      } else if (req.method === "GET" && /^\/api\/ranked\/entries\//.test(url.pathname)) {
        respond(res, 200, await store.detail(url.pathname.split("/").at(-1)));
      } else if (req.method === "POST") {
        const user = await account.authorize(req, true), data = await body(req);
        const now = Date.now();
        for (const [key,value] of limits) if (value.until < now) limits.delete(key);
        if (!limits.has(user.id)) limits.set(user.id,{until:now+60000,count:0});
        if (++limits.get(user.id).count > 100 || limits.size > 5000) fail("rate_limited",429);
        if (url.pathname === "/api/ranked/runs") respond(res, 201, { ticket: await store.start(user.id, data.starter_id) });
        else {
          const route = /^\/api\/ranked\/runs\/([^/]+)\/(commands|finish)$/.exec(url.pathname);
          if (!route) fail("not_found", 404);
          respond(res, 200, route[2] === "commands" ? await store.append(user.id, route[1], data.sequence, data.commands) : await store.finish(user.id, route[1], data.sequence, data.disqualified));
        }
      } else respond(res, 405, { error: "method_not_allowed" });
    } catch (error) { respond(res, error.status || 503, { error: error.status ? error.code : "rankings_unavailable" }); }
    return true;
  } };
}
module.exports = { createRankingService };
