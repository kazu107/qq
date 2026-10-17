"use strict";
const { CloudSaveStore } = require("./store");
function createCloudService(account) {
  let store; const limits = new Map();
  return { async handle(req, res) {
    const pathname = new URL(req.url, "http://internal").pathname;
    if (!pathname.startsWith("/api/cloud/")) return false;
    res.setHeader("Cache-Control", "no-store"); res.setHeader("Vary", "Cookie");
    res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
    function send(code, data) { res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" }); res.end(JSON.stringify(data)); }
    try {
      const user = await account.authorize(req, req.method !== "GET");
      if (req.headers["x-qq-account"] !== user.id) throw Object.assign(new Error(), { status: 409, code: "account_changed" });
      const now = Date.now();
      for (const [key, value] of limits) if (value.until < now) limits.delete(key);
      if (!limits.has(user.id)) limits.set(user.id, { count: 0, until: now + 60000 });
      if (++limits.get(user.id).count > 180 || limits.size > 5000) throw Object.assign(new Error(), { status: 429, code: "rate_limited" });
      store ||= new CloudSaveStore((await account.storage()).pool);
      const writer = req.headers["x-qq-writer"] || "";
      if (req.method === "GET" && pathname === "/api/cloud/save") send(200, await store.read(user.id, writer));
      else if (req.method === "GET" && pathname === "/api/cloud/history") send(200, { history: await store.history(user.id) });
      else if (["POST", "PUT"].includes(req.method)) {
        if (req.headers["content-type"]?.split(";")[0] !== "application/json") throw Object.assign(new Error(), { status: 400, code: "invalid_json" });
        const chunks = []; let size = 0;
        for await (const chunk of req) { size += chunk.length; if (size > 4100000) throw Object.assign(new Error(), { status: 413, code: "save_too_large" }); chunks.push(chunk); }
        let body; try { body = JSON.parse(Buffer.concat(chunks).toString()); if (!body || typeof body !== "object" || Array.isArray(body)) throw Error(); }
        catch { throw Object.assign(new Error(), { status: 400, code: "invalid_json" }); }
        if (pathname === "/api/cloud/claim" && req.method === "POST") send(200, await store.claim(user.id, body.writer_id, body.device_label, body.takeover));
        else if (["/api/cloud/lease", "/api/cloud/release"].includes(pathname) && req.method === "POST") send(200, await store.lease(user.id, body.writer_id, pathname.endsWith("release")));
        else if (pathname === "/api/cloud/save" && req.method === "PUT") send(200, await store.write(user.id, body));
        else if (pathname === "/api/cloud/restore" && req.method === "POST") send(200, await store.write(user.id, body, body.revision));
        else send(404, { error: "not_found" });
      } else send(405, { error: "method_not_allowed" });
    } catch (error) { send(error.status || 503, { error: error.code || "cloud_unavailable" }); }
    return true;
  } };
}
module.exports = { createCloudService };
