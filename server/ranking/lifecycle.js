"use strict";
const { RankingStore, rules, fail } = require("./store");

async function controlled(pool, action) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(hashtextextended('qq-ranked-seasons',0))");
    const control = (await client.query("SELECT * FROM qq_ranked_control WHERE singleton=true FOR UPDATE")).rows[0];
    if (!control) fail("control_missing", 503);
    const result = await action(client, control);
    await client.query("COMMIT");
    return result;
  } catch (error) { await client.query("ROLLBACK"); throw error; }
  finally { client.release(); }
}

async function pause(pool) {
  return controlled(pool, async (client, control) => {
    await client.query("UPDATE qq_ranked_control SET state='preparing' WHERE singleton=true");
    return { status: "preparing", generation: control.generation };
  });
}

async function startSeason(pool, expectedRuleset, generation, definition = rules) {
  if (expectedRuleset !== definition.ruleset) fail("ruleset_confirmation_required");
  return controlled(pool, async (client, control) => {
    if (generation !== control.generation) fail("generation_confirmation_required");
    // A repeat or concurrent start is idempotent; only a preparing state can open.
    const season = await new RankingStore(pool, definition).seasonInTransaction(client);
    await client.query("UPDATE qq_ranked_control SET state='active' WHERE singleton=true");
    return { status: "active", season };
  });
}

async function whileActive(pool, action) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const control = (await client.query("SELECT state FROM qq_ranked_control WHERE singleton=true FOR SHARE")).rows[0];
    const result = control?.state === "active" ? await action(client) : null;
    await client.query("COMMIT");
    return result;
  } catch (error) { await client.query("ROLLBACK"); throw error; }
  finally { client.release(); }
}

module.exports = { controlled, pause, startSeason, whileActive };
