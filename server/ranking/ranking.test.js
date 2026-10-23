"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { accountFixture, BrowserSession, testDatabaseEnv } = require("../../tests/helpers/account_fixture");
const { RankingStore, seasonAt, validateCommands, rules } = require("./store");

test("JST season boundaries, command schemas and privileged methods", () => {
  assert.equal(require("./build.json").game_version,require("../../data/version_history.json").current_version);
  assert.deepEqual(rules.starters, require("../../data/starters.json").map(starter=>starter.id));
  const fs = require("node:fs");
  assert.equal(rules.ruleset,/const RULESET := "([^"]+)"/.exec(fs.readFileSync(require("node:path").join(__dirname,"../../src/autoload/RankedSession.gd"),"utf8"))[1]);
  assert.equal(seasonAt(new Date("2026-10-31T14:59:59Z")).id, `${rules.ruleset}:2026-10`);
  assert.equal(seasonAt(new Date("2026-10-31T15:00:00Z")).id, `${rules.ruleset}:2026-11`);
  assert.throws(() => validateCommands([{ kind: "game", method: "developer_add_gold", args: [10] }]));
  assert.throws(() => validateCommands([{ kind: "advance", ticks: -1 }]));
  assert.throws(() => validateCommands([{ kind: "advance", ticks: 1, injected: "unexpected" }]));
  assert.throws(() => validateCommands([{ kind: "game", method: "equip_card", args: [] }]));
  assert.throws(() => validateCommands([{ kind: "game", method: "equip_card", args: [{ id: "strike" }] }]));
  assert.doesNotThrow(() => validateCommands([{ kind: "game", method: "equip_card", args: ["strike"] }]));
});

test("ranked ownership, CSRF, idempotence, seasons, best records and developer permissions", { skip: !testDatabaseEnv() }, async t => {
  const fixture = await accountFixture({ extraEnv: { DEVELOPER_USERNAMES: "DevUser" } });
  const { origin, store, mock } = fixture;
  try {
    const guest = new BrowserSession(origin);
    assert.equal((await guest.profile()).canDeveloper, false);
    assert.equal((await guest.request("/rankings")).status, 200);
    assert.equal((await guest.request("/api/ranked/board")).status, 200);
    assert.equal((await guest.write("/api/ranked/runs", { starter_id: "balanced" })).status, 401);
    const first = new BrowserSession(origin), second = new BrowserSession(origin);
    await first.login();
    await first.write("/api/account/username", { username: "DevUser", canDeveloper: false });
    assert.equal((await first.profile()).canDeveloper, true);
    mock.state.googleSubject = "ranking-second-user";
    await second.login();
    await second.write("/api/account/username", { username: "RegularUser", canDeveloper: true });
    assert.equal((await second.profile()).canDeveloper, false);
    await t.test("start ignores caller identity/seed and enforces CSRF", async () => {
      assert.equal((await first.write("/api/ranked/runs", { starter_id: "balanced" }, { Origin: "https://attacker.invalid" })).status, 403);
      assert.equal((await first.write("/api/ranked/runs", { starter_id: "unknown" })).status, 400);
    });
    const created = await (await first.write("/api/ranked/runs", { starter_id: "balanced", seed: -100, user_id: (await second.profile()).user.id })).json();
    const run = created.ticket;
    assert.equal(run.user_id, (await first.profile()).user.id);
    assert(run.seed > 0 && run.ruleset === rules.ruleset);
    const commands = [{ kind: "game", method: "select_map_node", args: ["step_0_node_0"] }];
    assert.equal((await second.write(`/api/ranked/runs/${run.id}/commands`, { sequence: 0, commands })).status, 404);
    assert.equal((await first.write(`/api/ranked/runs/${run.id}/commands`, { sequence: 1, commands })).status, 409);
    for(let i=0;i<2;i++) assert.equal((await first.write(`/api/ranked/runs/${run.id}/commands`, { sequence: 0, commands })).status, 200);
    const journal = await (await first.request(`/api/ranked/runs/${run.id}/journal?from=0`)).json();
    assert.deepEqual(journal.commands,commands);
    assert.equal(journal.next_sequence,1);
    assert.equal((await second.request(`/api/ranked/runs/${run.id}/journal?from=0`)).status,404);
    assert.equal((await second.request(`/api/ranked/runs/${run.id}`)).status,404);
    assert.equal((await first.request(`/api/ranked/runs/${run.id}`)).status,200);
    assert.equal((await first.write(`/api/ranked/runs/${run.id}/commands`, { sequence: 0, commands: [{ kind: "start" }] })).status, 409);
    assert.equal((await first.write(`/api/ranked/runs/${run.id}/finish`, { sequence: 0 })).status, 409);
    assert.equal((await first.write(`/api/ranked/runs/${run.id}/finish`, { sequence: 1, total_score: 999999999 })).status, 200);
    const board = await (await guest.request("/api/ranked/board")).json();
    assert.deepEqual(board.entries, []);
    assert.equal((await store.pool.query("SELECT result FROM qq_ranked_runs WHERE id=$1",[run.id])).rows[0].result,null);
    assert.equal((await first.write(`/api/ranked/runs/${run.id}/finish`, { sequence: 1 })).status, 200);
    assert.equal((await first.write(`/api/ranked/runs/${run.id}/commands`, { sequence: 1, commands })).status, 409);
    assert.equal((await guest.request(`/api/ranked/entries/${run.id}`)).status, 404);
    // Only the trusted verifier's derived results may become leaderboard candidates.
    await store.pool.query("UPDATE qq_ranked_runs SET status='verified',result=$2 WHERE id=$1", [run.id, { total_score: 1000, reached_step: 2 }]);
    const rankStore = new RankingStore(store.pool);
    const best = await rankStore.start(run.user_id, "tempo");
    await store.pool.query("UPDATE qq_ranked_runs SET status='verified',finished_at=now(),result=$2 WHERE id=$1", [best.id, { total_score: 2000, reached_step: 3 }]);
    const tied = await rankStore.start((await second.profile()).user.id, "balanced");
    await store.pool.query("UPDATE qq_ranked_runs SET status='verified',finished_at=now(),result=$2 WHERE id=$1", [tied.id, { total_score: 2000, reached_step: 3 }]);
    const verified = await (await first.request("/api/ranked/board")).json();
    assert.equal(verified.entries.length, 2);
    assert(verified.entries.every(entry=>entry.rank===1));
    assert.equal(verified.self.result.total_score, 2000);
    const filtered = await rankStore.board(run.season_id, "balanced", run.user_id);
    assert.equal(filtered.self.result.total_score,1000);
    assert.equal((await guest.request(`/api/ranked/entries/${run.id}`)).status, 200);
    const history = await (await first.request("/api/ranked/history")).json();
    assert.equal(history.runs.length, 2);
    const disqualified = await rankStore.start(run.user_id, "balanced");
    assert.equal((await rankStore.finish(run.user_id,disqualified.id,0,true)).status, "disqualified");
    const old = await rankStore.start(run.user_id, "balanced");
    await store.pool.query("UPDATE qq_ranked_seasons SET ends_at=now()-interval '1 second' WHERE id=$1", [old.season_id]);
    assert.equal((await rankStore.finish(run.user_id,old.id,0,false)).status,"rejected");
  } finally { await fixture.close(); }
});
