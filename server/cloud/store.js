"use strict";
const { createHash, randomUUID } = require("node:crypto");
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const RESUME_KEYS = new Set(["screen_hint", "pending_enemy_id", "reward_options", "last_battle_summary", "last_reward_bundle", "last_run_starter_id", "last_run_seed", "last_run_infinite", "settings_return_hint"]);
function fail(code, status = 400) { throw Object.assign(new Error(code), { code, status }); }
function guestCredential(ticket) {
  if (!ticket || !UUID.test(ticket.origin_id || ticket.id || "") || !/^[A-Za-z0-9_-]{43}$/.test(ticket.secret || "")) fail("invalid_guest_ticket");
  return createHash("sha256").update(ticket.secret).digest("hex");
}
function receipt(row) { return row.claimed_by ? { id: row.id, origin_id: row.origin_id, owner_id: row.claimed_by, revision: row.import_revision, claimed_at: row.claimed_at } : null; }
function validatePayload(data, owner) {
  if (!data || data.schema_version !== 1 || Object.keys(data).some(key => !["schema_version", "current_run", "suspended_runs", "meta_progress", "settings"].includes(key))) fail("invalid_save");
  for (const key of ["current_run", "suspended_runs", "meta_progress", "settings"]) if (!data[key] || typeof data[key] !== "object" || Array.isArray(data[key])) fail("invalid_save");
  if (Object.keys(data.settings).some(key => !RESUME_KEYS.has(key))) fail("device_settings_not_allowed");
  let nodes = 0;
  function visit(value, depth = 0) {
    if (++nodes > 250000 || depth > 48) fail("save_too_complex");
    if (typeof value === "number" && (!Number.isFinite(value) || Math.abs(value) > 1e16)) fail("invalid_save");
    if (value && typeof value === "object") {
      for (const [key, child] of Object.entries(value)) {
        if (["__proto__", "prototype", "constructor"].includes(key)) fail("invalid_save");
        if (key === "ticket" && child?.user_id && child.user_id !== owner) fail("foreign_ranked_run", 403);
        visit(child, depth + 1);
      }
    }
  }
  visit(data);
  const json = JSON.stringify(data);
  if (Buffer.byteLength(json) > 4000000) fail("save_too_large", 413);
  return { json, hash: createHash("sha256").update(json).digest("hex") };
}
function view(row, writer = "", includeData = true) {
  return { revision: row.revision, updated_at: row.updated_at, request_id: row.request_id, ...(includeData ? { payload: row.payload } : {}),
    device_label: row.device_label, lease_until: row.lease_until,
    writer_active: !!row.writer_id && new Date(row.lease_until) > new Date(), owns_lease: row.writer_id === writer && new Date(row.lease_until) > new Date() };
}
class CloudSaveStore {
  constructor(pool) { this.pool = pool; }
  async read(user, writer) {
    const result = await this.pool.query("SELECT * FROM qq_cloud_saves WHERE user_id=$1", [user]);
    return result.rowCount ? view(result.rows[0], writer) : { revision: 0, payload: null, writer_active: false, owns_lease: false };
  }
  async transaction(user, fn) {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("INSERT INTO qq_cloud_saves(user_id) VALUES($1) ON CONFLICT DO NOTHING", [user]);
      const row = (await client.query("SELECT * FROM qq_cloud_saves WHERE user_id=$1 FOR UPDATE", [user])).rows[0];
      const result = await fn(client, row);
      await client.query("COMMIT"); return result;
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async claim(user, writer, label, takeover) {
    if (!UUID.test(writer)) fail("invalid_writer");
    return this.transaction(user, async (client, row) => {
      if (row.writer_id && row.writer_id !== writer && new Date(row.lease_until) > new Date() && takeover !== true) fail("device_busy", 409);
      const result = await client.query("UPDATE qq_cloud_saves SET writer_id=$2,device_label=$3,lease_until=now()+interval '50 seconds' WHERE user_id=$1 RETURNING *", [user, writer, String(label || "Browser").slice(0, 48)]);
      return view(result.rows[0], writer);
    });
  }
  async lease(user, writer, release = false) {
    if (!UUID.test(writer)) fail("invalid_writer");
    const result = await this.pool.query("UPDATE qq_cloud_saves SET lease_until=CASE WHEN $3 THEN now() ELSE now()+interval '50 seconds' END WHERE user_id=$1 AND writer_id=$2 AND lease_until>now() RETURNING *", [user, writer, release]);
    if (!result.rowCount) fail("lease_lost", 409);
    return view(result.rows[0], writer, false);
  }
  async createGuest(user, identity) {
    if (!UUID.test(identity?.origin_id || "")) fail("invalid_guest_ticket");
    const hash = guestCredential(identity);
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", ["guest-origin:" + identity.origin_id]);
      let existing = (await client.query("SELECT * FROM qq_guest_transfers WHERE origin_id=$1", [identity.origin_id])).rows[0];
      if (existing) {
        if (existing.token_hash !== hash) fail("guest_ticket_not_found", 404);
        await client.query("COMMIT");
        return { guest_ticket: { id: existing.id, origin_id: existing.origin_id, secret: identity.secret }, guest_receipt: receipt(existing) };
      }
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", ["guest-issue:" + user]);
      const count = await client.query("SELECT count(*) FROM qq_guest_transfers WHERE issued_by=$1 AND created_at>now()-interval '1 hour'", [user]);
      if (Number(count.rows[0].count) >= 20) fail("guest_issue_rate_limited", 429);
      const ticket = { id: randomUUID(), origin_id: identity.origin_id, secret: identity.secret };
      await client.query("INSERT INTO qq_guest_transfers(id,origin_id,token_hash,issued_by) VALUES($1,$2,$3,$4)", [ticket.id, ticket.origin_id, hash, user]);
      await client.query("COMMIT"); return { guest_ticket: ticket, guest_receipt: null };
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async guestStatus(user, ticket) {
    const hash = guestCredential(ticket);
    const result = await this.pool.query("SELECT * FROM qq_guest_transfers WHERE origin_id=$1 AND token_hash=$2", [ticket.origin_id || ticket.id, hash]);
    if (!result.rowCount) return { status: "unregistered", guest_receipt: null };
    const row = result.rows[0];
    // Possession of the source capability permits checking its destination, never reading that account's save.
    return { status: row.claimed_by ? row.claimed_by === user ? "claimed_here" : "claimed_elsewhere" : "available", guest_receipt: receipt(row) };
  }
  async importGuest(user, body) {
    guestCredential(body.guest_ticket);
    if (!UUID.test(body.guest_ticket.id || "")) fail("invalid_guest_ticket");
    return this.write(user, body, null, body.guest_ticket);
  }
  async write(user, body, restoreRevision = null, guestTicket = null) {
    if (!UUID.test(body.writer_id) || !UUID.test(body.request_id) || !Number.isInteger(body.base_revision) || body.base_revision < 0) fail("invalid_revision");
    const validated = restoreRevision === null ? validatePayload(body.payload, user) : null;
    return this.transaction(user, async (client, row) => {
      let guest;
      if (guestTicket) {
        guest = (await client.query("SELECT * FROM qq_guest_transfers WHERE id=$1 AND token_hash=$2 FOR UPDATE", [guestTicket.id, guestCredential(guestTicket)])).rows[0];
        if (!guest) fail("guest_ticket_not_found", 404);
        if (guest.claimed_by) {
          if (guest.claimed_by !== user) throw Object.assign(new Error("guest_already_claimed"), { code: "guest_already_claimed", status: 409, guest_receipt: receipt(guest) });
          return { ...view(row, body.writer_id), already_imported: true, guest_receipt: receipt(guest) };
        }
      }
      if (!guest && validated && row.request_id === body.request_id && row.writer_id === body.writer_id && row.payload_hash === validated.hash) return view(row, body.writer_id, false);
      if (row.writer_id !== body.writer_id || new Date(row.lease_until) <= new Date()) fail("lease_lost", 409);
      if (row.revision !== body.base_revision) fail("revision_conflict", 409);
      let payload = validated;
      if (restoreRevision !== null) {
        if (!Number.isInteger(restoreRevision)) fail("invalid_revision");
        const backup = await client.query("SELECT payload FROM qq_cloud_save_history WHERE user_id=$1 AND revision=$2", [user, restoreRevision]);
        if (!backup.rowCount) fail("backup_not_found", 404);
        payload = validatePayload(backup.rows[0].payload, user);
      }
      if (row.payload) await client.query("INSERT INTO qq_cloud_save_history(user_id,revision,payload,updated_at) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING", [user, row.revision, row.payload, row.updated_at]);
      const result = await client.query("UPDATE qq_cloud_saves SET payload=$2,revision=revision+1,updated_at=now(),lease_until=now()+interval '50 seconds',request_id=$3,payload_hash=$4 WHERE user_id=$1 RETURNING *", [user, payload.json, body.request_id, payload.hash]);
      if (guest) {
        guest = (await client.query("UPDATE qq_guest_transfers SET claimed_by=$2,claimed_at=now(),import_revision=$3,request_id=$4 WHERE id=$1 RETURNING *", [guest.id, user, result.rows[0].revision, body.request_id])).rows[0];
      }
      await client.query("DELETE FROM qq_cloud_save_history WHERE user_id=$1 AND revision NOT IN (SELECT revision FROM qq_cloud_save_history WHERE user_id=$1 ORDER BY revision DESC LIMIT 5)", [user]);
      return { ...view(result.rows[0], body.writer_id, restoreRevision !== null || !!guest), ...(guest ? { guest_receipt: receipt(guest), already_imported: false } : {}) };
    });
  }
  async history(user) { return (await this.pool.query("SELECT revision,updated_at FROM qq_cloud_save_history WHERE user_id=$1 ORDER BY revision DESC LIMIT 5", [user])).rows; }
}
module.exports = { CloudSaveStore, validatePayload };
