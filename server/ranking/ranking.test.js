"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { accountFixture, BrowserSession, testDatabaseEnv } = require("../../tests/helpers/account_fixture");
const { RankingStore, seasonAt, groupSeasons, selectBoard, validateCommands, rules } = require("./store");
const { randomUUID } = require("node:crypto");

test("JST season boundaries, command schemas and privileged methods", () => {
  assert.equal(require("./build.json").game_version,require("../../data/version_history.json").current_version);
  assert.deepEqual(rules.starters, require("../../data/starters.json").map(starter=>starter.id));
  const fs = require("node:fs");
  assert.equal(rules.ruleset,/const RULESET := "([^"]+)"/.exec(fs.readFileSync(require("node:path").join(__dirname,"../../src/autoload/RankedSession.gd"),"utf8"))[1]);
  assert.equal(seasonAt(new Date("2026-10-31T14:59:59Z")).id, "2026-10");
  assert.equal(seasonAt(new Date("2026-10-31T15:00:00Z")).id, "2026-11");
  assert.equal(seasonAt(new Date("2026-12-31T15:00:00Z")).id, "2027-01");
  assert.throws(() => validateCommands([{ kind: "game", method: "developer_add_gold", args: [10] }]));
  assert.throws(() => validateCommands([{ kind: "advance", ticks: -1 }]));
  assert.throws(() => validateCommands([{ kind: "advance", ticks: 1, injected: "unexpected" }]));
  assert.throws(() => validateCommands([{ kind: "game", method: "equip_card", args: [] }]));
  assert.throws(() => validateCommands([{ kind: "game", method: "equip_card", args: [{ id: "strike" }] }]));
  assert.doesNotThrow(() => validateCommands([{ kind: "game", method: "equip_card", args: ["strike"] }]));
});

test("calendar seasons group legacy rule buckets without mixing leaderboard rules", () => {
  const current = seasonAt(new Date("2026-10-24T00:00:00Z"));
  const rows = ["infinite-1", "infinite-2", rules.ruleset].map(ruleset => ({ id: `${ruleset}:2026-10`, ruleset, starts_at: current.startsAt, ends_at: current.endsAt }));
  rows.push({ id: "2026-10", ruleset: "infinite-1", run_rulesets: [rules.ruleset], starts_at: current.startsAt, ends_at: current.endsAt });
  const months = groupSeasons(rows, current);
  assert.equal(months.length, 1);
  assert.equal(months[0].id, "2026-10");
  assert.deepEqual(months[0].rulesets, ["infinite-1", "infinite-2", rules.ruleset]);
  assert.deepEqual(selectBoard(months, "", "", current), { season_id: "2026-10", ruleset: rules.ruleset });
  assert.deepEqual(selectBoard(months, "infinite-1:2026-10", "", current), { season_id: "2026-10", ruleset: "infinite-1" });
  assert.deepEqual(selectBoard(months, "2026-10", "infinite-2", current), { season_id: "2026-10", ruleset: "infinite-2" });
  const past = { id: "2026-09", rulesets: ["infinite-9", "infinite-10"] };
  assert.equal(selectBoard([past], "2026-09", "", current).ruleset, "infinite-10");
  for (const value of ["2026-00", "2026-13", "invalid", "1999-10", "2026-10;DROP"]) assert.throws(() => selectBoard(months, value, "", current));
  assert.throws(() => selectBoard(months, "2026-10", "infinite-3' OR 1=1", current));
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
    assert.equal(run.season_id, seasonAt().id);
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
    await t.test("legacy October buckets retain runs, deduplicate per user and expose one calendar month", async () => {
      const period = seasonAt();
      const expectedIds = [run.id, best.id, tied.id];
      for (const rule of ["infinite-1", "infinite-2", rules.ruleset]) {
        const legacyId = `${rule}:${period.id}`;
        await store.pool.query("INSERT INTO qq_ranked_seasons(id,ruleset,starts_at,ends_at) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING", [legacyId, rule, period.startsAt, period.endsAt]);
        const id = randomUUID();
        expectedIds.push(id);
        await store.pool.query(`INSERT INTO qq_ranked_runs(id,user_id,season_id,ruleset,seed,starter_id,status,finished_at,result)
          VALUES($1,$2,$3,$4,1234,'balanced','verified',now(),$5)`, [id, run.user_id, legacyId, rule, { total_score: rule === rules.ruleset ? 1500 : 99000, reached_step: 10 }]);
      }
      const merged = await (await first.request("/api/ranked/board")).json();
      assert.equal(merged.seasons.filter(month => month.id === period.id).length, 1);
      assert.deepEqual(merged.seasons.find(month => month.id === period.id).rulesets, ["infinite-1", "infinite-2", rules.ruleset]);
      assert.equal(merged.selection.ruleset, rules.ruleset);
      assert.equal(merged.entries.length, 2);
      assert.equal(merged.self.result.total_score, 2000);
      assert(merged.entries.every(entry => entry.ruleset === rules.ruleset));
      const sameRule = await rankStore.board(period.id, "balanced", run.user_id);
      assert.equal(sameRule.self.result.total_score, 1500, "same-rule records in legacy and calendar buckets must share a personal best");
      const previous = await (await first.request(`/api/ranked/board?season=${period.id}&ruleset=infinite-1`)).json();
      assert.equal(previous.self.result.total_score, 99000);
      assert.equal(previous.entries.length, 1);
      const legacyUrl = await (await first.request(`/api/ranked/board?season=infinite-1:${period.id}`)).json();
      assert.deepEqual(legacyUrl.entries, previous.entries);
      const activeId = randomUUID();
      await store.pool.query(`INSERT INTO qq_ranked_runs(id,user_id,season_id,ruleset,seed,starter_id)
        VALUES($1,$2,$3,$4,1234,'balanced')`, [activeId, run.user_id, `${rules.ruleset}:${period.id}`, rules.ruleset]);
      await rankStore.append(run.user_id, activeId, 0, commands);
      const active = await rankStore.journal(run.user_id, activeId, 0);
      assert.equal(active.ticket.season_id, `${rules.ruleset}:${period.id}`, "active legacy tickets must not be rewritten");
      assert.deepEqual(active.commands, commands);
      assert.equal((await rankStore.finish(run.user_id, activeId, 1, false)).status, "pending");
      assert.equal((await store.pool.query("SELECT count(*) FROM qq_ranked_runs WHERE id=ANY($1::uuid[])", [expectedIds])).rows[0].count, String(expectedIds.length));
      const past = seasonAt(new Date(period.startsAt.getTime() - 1));
      for (const rule of ["infinite-9", "infinite-10"]) {
        await store.pool.query("INSERT INTO qq_ranked_seasons(id,ruleset,starts_at,ends_at) VALUES($1,$2,$3,$4)", [`${rule}:${past.id}`, rule, past.startsAt, past.endsAt]);
      }
      const pastBoard = await (await guest.request(`/api/ranked/board?season=${past.id}`)).json();
      assert.equal(pastBoard.selection.ruleset, "infinite-10");
      assert.equal(pastBoard.seasons.filter(month => month.id === past.id).length, 1);
      assert.equal((await guest.request("/api/ranked/board?season=2026-13")).status, 400);
    });
    const disqualified = await rankStore.start(run.user_id, "balanced");
    assert.equal((await rankStore.finish(run.user_id,disqualified.id,0,true)).status, "disqualified");
    const old = await rankStore.start(run.user_id, "balanced");
    await store.pool.query("UPDATE qq_ranked_seasons SET ends_at=now()-interval '1 second' WHERE id=$1", [old.season_id]);
    assert.equal((await rankStore.finish(run.user_id,old.id,0,false)).status,"rejected");
  } finally { await fixture.close(); }
});
