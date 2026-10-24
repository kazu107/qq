"use strict";

const { randomUUID, randomInt } = require("node:crypto");
const { isDeepStrictEqual } = require("node:util");
const rules = require("./rules.json");
const METHODS = new Set(["select_map_node", "start_active_encounter", "prepare_next_battle", "choose_reward", "skip_reward", "reroll_rewards_for_gold", "equip_card", "unequip_card", "sell_loadout_card", "buy_shop_offer", "use_shop_service_choice", "upgrade_forge_card", "use_forge_service_choice", "use_heal_node_choice", "resolve_event_choice", "continue_hazard", "withdraw_hazard", "leave_facility"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NO_ARGS = new Set(["start_active_encounter", "prepare_next_battle", "skip_reward", "reroll_rewards_for_gold", "continue_hazard", "withdraw_hazard", "leave_facility"]);
function fail(code, status = 400) { throw Object.assign(new Error(code), { code, status }); }
const SEASON_ID = /^season-([1-9][0-9]{0,8})$/;
function seasonNumber(id) {
  const match = typeof id === "string" && SEASON_ID.exec(id);
  if (!match) fail("invalid_filter");
  return Number(match[1]);
}
function publicSeason(row) {
  return { id: row.id, number: seasonNumber(row.id), startsAt: row.starts_at, endsAt: row.ends_at };
}
function ruleRevision(value) {
  const match = /^infinite-([1-9][0-9]*)$/.exec(value);
  if (!match) fail("invalid_ruleset", 503);
  return Number(match[1]);
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
  constructor(pool, definition = rules) { this.pool = pool; this.rules = definition; this.season = null; }
  async ensureSeason() {
    if (this.season) return this.season;
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended('qq-ranked-seasons',0))");
      const result = await client.query("SELECT * FROM qq_ranked_seasons WHERE id ~ '^season-[1-9][0-9]{0,8}$' ORDER BY substring(id FROM 8)::integer DESC LIMIT 1 FOR UPDATE");
      const latest = result.rows[0];
      let current;
      if (latest?.ruleset === this.rules.ruleset) {
        if (latest.ends_at !== null) fail("season_closed", 409);
        current = latest;
      } else {
        // An old dyno must not roll a freshly deployed season back to older gameplay.
        if (latest && ruleRevision(this.rules.ruleset) <= ruleRevision(latest.ruleset)) fail("season_update_required", 409);
        const cutoff = (await client.query("SELECT clock_timestamp() AS cutoff")).rows[0].cutoff;
        await client.query("UPDATE qq_ranked_seasons SET ends_at=$1 WHERE ends_at IS NULL OR ends_at>$1", [cutoff]);
        const number = latest ? seasonNumber(latest.id) + 1 : 1;
        current = (await client.query("INSERT INTO qq_ranked_seasons(id,ruleset,starts_at,ends_at) VALUES($1,$2,$3,NULL) RETURNING *", [`season-${number}`, this.rules.ruleset, cutoff])).rows[0];
      }
      await client.query("COMMIT");
      this.season = publicSeason(current);
      return this.season;
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async start(userId, starterId) {
    if (!this.rules.starters.includes(starterId)) fail("invalid_starter");
    const season = await this.ensureSeason();
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", ["rank-start:" + userId]);
      const open = await client.query("SELECT id FROM qq_ranked_seasons WHERE id=$1 AND ends_at IS NULL FOR SHARE", [season.id]);
      if (!open.rowCount) fail("season_closed", 409);
      const recent = await client.query("SELECT count(*) FROM qq_ranked_runs WHERE user_id=$1 AND created_at>now()-interval '1 hour'", [userId]);
      if (Number(recent.rows[0].count) >= 20) fail("start_rate_limited", 429);
      const result = await client.query(`INSERT INTO qq_ranked_runs(id,user_id,season_id,ruleset,seed,starter_id) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,
        [randomUUID(), userId, season.id, this.rules.ruleset, randomInt(1, 2147483647), starterId]);
      await client.query("COMMIT");
      return ticket(result.rows[0]);
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async owned(client, userId, id) {
    if (!UUID.test(id)) fail("not_found", 404);
    const result = await client.query("SELECT r.*,s.ends_at FROM qq_ranked_runs r JOIN qq_ranked_seasons s ON s.id=r.season_id WHERE r.id=$1 AND user_id=$2 FOR UPDATE OF r FOR SHARE OF s", [id, userId]);
    if (!result.rowCount) fail("not_found", 404);
    return result.rows[0];
  }
  async append(userId, id, sequence, commands) {
    validateCommands(commands);
    if (!Number.isInteger(sequence) || sequence < 0 || sequence + commands.length > 200000) fail("record_limit");
    const season = await this.ensureSeason();
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const row = await this.owned(client, userId, id);
      if (row.status !== "active") fail("run_closed", 409);
      if (row.ruleset !== this.rules.ruleset || row.season_id !== season.id || row.ends_at !== null && new Date(row.ends_at) <= new Date()) fail("season_closed", 409);
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
    const season = await this.ensureSeason();
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const row = await this.owned(client, userId, id);
      if (row.status !== "active") { await client.query("COMMIT"); return { status: row.status }; }
      if (row.next_sequence !== sequence) fail("sequence_gap", 409);
      const expired = row.ruleset !== this.rules.ruleset || row.season_id !== season.id || row.ends_at !== null && new Date(row.ends_at) <= new Date();
      const status = disqualified === true ? "disqualified" : expired ? "rejected" : "pending";
      await client.query("UPDATE qq_ranked_runs SET status=$2,reason=$3,finished_at=now(),updated_at=now() WHERE id=$1", [id, status, disqualified ? "developer_or_invalid_run" : expired ? "season_closed" : null]);
      await client.query("COMMIT"); return { status };
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }
  async listSeasons() {
    await this.ensureSeason();
    const result = await this.pool.query("SELECT * FROM qq_ranked_seasons WHERE id ~ '^season-[1-9][0-9]{0,8}$' ORDER BY substring(id FROM 8)::integer DESC LIMIT 24");
    return result.rows.map(publicSeason);
  }
  async board(season, starter = "", userId = null, page = 0) {
    if (typeof season !== "string" || season.length > 70 || starter && !rules.starters.includes(starter)) fail("invalid_filter");
    seasonNumber(season);
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
    const rows = await this.pool.query("SELECT * FROM qq_ranked_runs WHERE user_id=$1 AND season_id ~ '^season-[1-9][0-9]{0,8}$' ORDER BY created_at DESC LIMIT 30", [userId]);
    return rows.rows.map(row => ({ ...publicRun(row), next_sequence: row.next_sequence }));
  }
  async journal(userId, id, from) {
    if (!Number.isInteger(from) || from < 0 || from > 200000) fail("invalid_sequence");
    const row = await this.owned(this.pool, userId, id);
    const commands = await this.pool.query("SELECT command FROM qq_ranked_commands WHERE run_id=$1 AND sequence >= $2 AND sequence < $3 ORDER BY sequence LIMIT 250", [id, from, row.next_sequence]);
    return { ticket: ticket(row), status: row.status, next_sequence: row.next_sequence, commands: commands.rows.map(item => item.command) };
  }
  async status(userId, id) {
    const row = await this.owned(this.pool, userId, id);
    return publicRun(row);
  }
  async detail(id) {
    if (!UUID.test(id)) fail("not_found", 404);
    const result = await this.pool.query("SELECT r.*,u.username FROM qq_ranked_runs r JOIN qq_accounts_users u ON u.id=r.user_id WHERE r.id=$1 AND status='verified'", [id]);
    if (!result.rowCount) fail("not_found", 404);
    return publicRun(result.rows[0]);
  }
}

module.exports = { RankingStore, rules, seasonNumber, publicSeason, ruleRevision, validateCommands, fail, ticket };
