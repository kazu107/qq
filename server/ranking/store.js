"use strict";

const { randomUUID, randomInt } = require("node:crypto");
const { isDeepStrictEqual } = require("node:util");
const rules = require("./rules.json");
const METHODS = new Set(["select_map_node", "start_active_encounter", "prepare_next_battle", "choose_reward", "skip_reward", "reroll_rewards_for_gold", "equip_card", "unequip_card", "sell_loadout_card", "buy_shop_offer", "use_shop_service_choice", "upgrade_forge_card", "use_forge_service_choice", "use_heal_node_choice", "resolve_event_choice", "continue_hazard", "withdraw_hazard", "leave_facility"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NO_ARGS = new Set(["start_active_encounter", "prepare_next_battle", "skip_reward", "reroll_rewards_for_gold", "continue_hazard", "withdraw_hazard", "leave_facility"]);
function fail(code, status = 400) { throw Object.assign(new Error(code), { code, status }); }
function seasonAt(now = new Date()) {
  const date = new Date(now.getTime() + 9 * 3600000), year = date.getUTCFullYear(), month = date.getUTCMonth();
  return { id: `${rules.ruleset}:${year}-${String(month + 1).padStart(2, "0")}`, ruleset: rules.ruleset,
    startsAt: new Date(Date.UTC(year, month, 1) - 9 * 3600000), endsAt: new Date(Date.UTC(year, month + 1, 1) - 9 * 3600000) };
}
function validateCommands(commands) {
  if (!Array.isArray(commands) || commands.length < 1 || commands.length > 250) fail("invalid_commands");
  for (const command of commands) {
    if (!command || typeof command !== "object" || Array.isArray(command) || JSON.stringify(command).length > 2048) fail("invalid_command");
    const fields = command.kind === "game" ? ["kind","method","args"] : command.kind === "setup" ? ["kind","enemy_id"] : command.kind === "advance" ? ["kind","ticks"] : ["card","start"].includes(command.kind) ? ["kind","runtime_id"] : ["kind"];
    if (Object.keys(command).some(key => !fields.includes(key))) fail("invalid_command");
    if (command.kind === "game") {
      if (!METHODS.has(command.method) || !Array.isArray(command.args) || command.args.length > 1 || command.args.some(value => !(typeof value === "string" && value.length <= 160) && !(Number.isSafeInteger(value) && value >= 0 && value <= 10000))) fail("invalid_command");
      if (command.args.length !== (NO_ARGS.has(command.method) ? 0 : 1)) fail("invalid_arguments");
      if (!NO_ARGS.has(command.method) && (command.method === "buy_shop_offer" ? !Number.isInteger(command.args[0]) : typeof command.args[0] !== "string")) fail("invalid_arguments");
    } else if (command.kind === "advance") {
      if (!Number.isInteger(command.ticks) || command.ticks < 1 || command.ticks > 3600) fail("invalid_ticks");
    } else if (command.kind === "setup") {
      if (typeof command.enemy_id !== "string" || !/^[a-z0-9_]{1,80}$/.test(command.enemy_id)) fail("invalid_enemy");
    } else if (command.kind === "card") {
      if (typeof command.runtime_id !== "string" || command.runtime_id.length > 160) fail("invalid_card");
    } else if (!["start", "complete"].includes(command.kind)) fail("invalid_command");
  }
}
function ticket(row) { return { id: row.id, user_id: row.user_id, season_id: row.season_id, ruleset: row.ruleset, seed: row.seed, starter_id: row.starter_id }; }
function publicRun(row) { return { id: row.id, username: row.username, starter_id: row.starter_id, season_id: row.season_id, status: row.status,
  finished_at: row.finished_at, result: row.result, reason: row.reason, rank: row.rank ? Number(row.rank) : undefined }; }

class RankingStore {
  constructor(pool) { this.pool = pool; this.season = null; }
  async ensureSeason() {
    const season = seasonAt();
    if (this.season?.id === season.id) return season;
    await this.pool.query("INSERT INTO qq_ranked_seasons(id,ruleset,starts_at,ends_at) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING", [season.id, season.ruleset, season.startsAt, season.endsAt]);
    this.season = season; return season;
  }
  async start(userId, starterId) {
    if (!rules.starters.includes(starterId)) fail("invalid_starter");
    const season = await this.ensureSeason();
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", ["rank-start:" + userId]);
      const recent = await client.query("SELECT count(*) FROM qq_ranked_runs WHERE user_id=$1 AND created_at>now()-interval '1 hour'", [userId]);
      if (Number(recent.rows[0].count) >= 20) fail("start_rate_limited", 429);
      const result = await client.query(`INSERT INTO qq_ranked_runs(id,user_id,season_id,ruleset,seed,starter_id) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,
        [randomUUID(), userId, season.id, rules.ruleset, randomInt(1, 2147483647), starterId]);
      await client.query("COMMIT");
      return ticket(result.rows[0]);
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async owned(client, userId, id) {
    if (!UUID.test(id)) fail("not_found", 404);
    const result = await client.query("SELECT r.*,s.ends_at FROM qq_ranked_runs r JOIN qq_ranked_seasons s ON s.id=r.season_id WHERE r.id=$1 AND user_id=$2 FOR UPDATE OF r", [id, userId]);
    if (!result.rowCount) fail("not_found", 404);
    return result.rows[0];
  }
  async append(userId, id, sequence, commands) {
    validateCommands(commands);
    if (!Number.isInteger(sequence) || sequence < 0 || sequence + commands.length > 200000) fail("record_limit");
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const row = await this.owned(client, userId, id);
      if (row.status !== "active") fail("run_closed", 409);
      if (row.ruleset !== rules.ruleset || new Date(row.ends_at) <= new Date()) fail("season_closed", 409);
      if (sequence > row.next_sequence) fail("sequence_gap", 409);
      for (let index = 0; index < commands.length; index++) {
        const number = sequence + index;
        if (number < row.next_sequence) {
          const prior = await client.query("SELECT command FROM qq_ranked_commands WHERE run_id=$1 AND sequence=$2", [id, number]);
          if (!prior.rowCount || !isDeepStrictEqual(prior.rows[0].command, commands[index])) fail("sequence_conflict", 409);
        } else await client.query("INSERT INTO qq_ranked_commands(run_id,sequence,command) VALUES($1,$2,$3)", [id, number, commands[index]]);
      }
      const next = Math.max(row.next_sequence, sequence + commands.length);
      await client.query("UPDATE qq_ranked_runs SET next_sequence=$2,updated_at=now() WHERE id=$1", [id, next]);
      await client.query("COMMIT"); return { next_sequence: next };
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async finish(userId, id, sequence, disqualified) {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const row = await this.owned(client, userId, id);
      if (row.status !== "active") { await client.query("COMMIT"); return { status: row.status }; }
      if (row.next_sequence !== sequence) fail("sequence_gap", 409);
      const expired = row.ruleset !== rules.ruleset || new Date(row.ends_at) <= new Date();
      const status = disqualified === true ? "disqualified" : expired ? "rejected" : "pending";
      await client.query("UPDATE qq_ranked_runs SET status=$2,reason=$3,finished_at=now(),updated_at=now() WHERE id=$1", [id, status, disqualified ? "developer_or_invalid_run" : expired ? "season_closed" : null]);
      await client.query("COMMIT"); return { status };
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async board(season, starter = "", userId = null, page = 0) {
    if (typeof season !== "string" || season.length > 70 || starter && !rules.starters.includes(starter)) fail("invalid_filter");
    const query = `WITH candidates AS (
      SELECT r.*,u.username,row_number() OVER(PARTITION BY r.user_id ORDER BY (r.result->>'total_score')::bigint DESC,r.finished_at,r.id) AS best
      FROM qq_ranked_runs r JOIN qq_accounts_users u ON u.id=r.user_id
      WHERE r.season_id=$1 AND r.status='verified' AND ($2='' OR r.starter_id=$2)
    ), ranked AS (SELECT *,dense_rank() OVER(ORDER BY (result->>'total_score')::bigint DESC) AS rank FROM candidates WHERE best=1)`;
    const result = await this.pool.query(query + " SELECT * FROM ranked ORDER BY (result->>'total_score')::bigint DESC,finished_at,id LIMIT 50 OFFSET $3", [season, starter, Math.min(200, Math.max(0, page)) * 50]);
    const own = userId ? await this.pool.query(query + " SELECT * FROM ranked WHERE user_id=$3", [season, starter, userId]) : { rows: [] };
    return { entries: result.rows.map(publicRun), self: own.rows[0] ? publicRun(own.rows[0]) : null };
  }
  async history(userId) {
    const rows = await this.pool.query("SELECT * FROM qq_ranked_runs WHERE user_id=$1 ORDER BY created_at DESC LIMIT 30", [userId]);
    return rows.rows.map(row => ({ ...publicRun(row), next_sequence: row.next_sequence }));
  }
  async detail(id) {
    if (!UUID.test(id)) fail("not_found", 404);
    const result = await this.pool.query("SELECT r.*,u.username FROM qq_ranked_runs r JOIN qq_accounts_users u ON u.id=r.user_id WHERE r.id=$1 AND status='verified'", [id]);
    if (!result.rowCount) fail("not_found", 404);
    return publicRun(result.rows[0]);
  }
}

module.exports = { RankingStore, rules, seasonAt, validateCommands, fail, ticket };
