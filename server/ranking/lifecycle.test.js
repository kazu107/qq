"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { accountFixture, BrowserSession, testDatabaseEnv } = require("../../tests/helpers/account_fixture");
const { RankingStore, rules, ruleRevision } = require("./store");
const { pause, startSeason } = require("./lifecycle");
const { exportRanking, resetAll } = require("./maintenance");
const { VerifierWorker } = require("./worker");

test("preparing survives migrations, visits and gameplay revisions; reset is backup-guarded and start is explicit", { skip: !testDatabaseEnv() }, async () => {
  const fixture = await accountFixture({ rankingState: "preparing" });
  try {
    const pool = fixture.store.pool;
    const service = new RankingStore(pool);
    const browser = new BrowserSession(fixture.origin);
    await browser.login(); await browser.write("/api/account/username", { username: "SeasonTester" });
    const owner = (await browser.profile()).user.id;
    await pool.query("INSERT INTO qq_cloud_saves(user_id,revision,payload) VALUES($1,8,$2)", [owner, { progress: "preserve", points: 99 }]);
    for (let index = 0; index < 3; index++) {
      await fixture.store.migrate();
      const availability = await (await browser.request("/api/ranked/availability")).json();
      assert.deepEqual(availability, { status: "preparing", next_season_number: 1 });
      const board = await (await browser.request("/api/ranked/board?season=season-99")).json();
      assert.equal(board.status, "preparing"); assert.equal(board.season, null);
      assert.equal(board.next_season_number, 1); assert.deepEqual(board.seasons, []);
      assert.equal(await new RankingStore(pool, { ...rules, ruleset: `infinite-${ruleRevision(rules.ruleset) + index}` }).ensureSeason(), null);
    }
    assert.equal((await browser.write("/api/ranked/runs", { starter_id: "balanced" })).status, 409);
    assert.equal((await (await browser.write("/api/ranked/runs", { starter_id: "balanced" })).json()).error, "ranked_preparing");
    assert.deepEqual((await (await browser.request("/api/ranked/history")).json()).runs, []);
    const generation = (await service.availability()).generation;
    await assert.rejects(startSeason(pool, "infinite-1", generation), { code: "ruleset_confirmation_required" });
    await assert.rejects(startSeason(pool, rules.ruleset, "incorrect"), { code: "generation_confirmation_required" });
    assert.equal((await pool.query("SELECT count(*) FROM qq_ranked_seasons")).rows[0].count, "0");
    const starts = await Promise.all(Array.from({ length: 4 }, () => startSeason(pool, rules.ruleset, generation)));
    assert(starts.every(item => item.season.id === "season-1"));
    const run = await service.start(owner, "balanced");
    await service.append(owner, run.id, 0, [{ kind: "start" }]);
    await service.finish(owner, run.id, 1, false);
    await pool.query("UPDATE qq_ranked_runs SET status='verifying',locked_by=$2 WHERE id=$1", [run.id, generation]);
    await pause(pool);
    const worker = new VerifierWorker({ storage: async () => fixture.store }, { AUTH_ENABLED: "true", RANKED_VERIFIER_ENABLED: "true" });
    let runtimeLoaded = false;
    worker.runtime = () => { runtimeLoaded = true; throw new Error("preparing_must_not_load_runtime"); };
    await worker.tick(); worker.stop();
    assert.equal(runtimeLoaded, false);
    await worker.complete(pool, run.id, generation, "verified", { total_score: 12345 }, null);
    assert.equal((await pool.query("SELECT status FROM qq_ranked_runs WHERE id=$1", [run.id])).rows[0].status, "verifying");
    await assert.rejects(service.append(owner, run.id, 1, [{ kind: "start" }]), { code: "ranked_preparing" });
    await assert.rejects(service.finish(owner, run.id, 1, false), { code: "ranked_preparing" });
    const backup = await exportRanking(pool);
    assert.equal(backup.data.seasons.length, 1); assert.equal(backup.data.runs.length, 1); assert.equal(backup.data.commands.length, 1);
    await assert.rejects(resetAll(pool, "0".repeat(64)), { code: "backup_mismatch" });
    await pool.query("UPDATE qq_ranked_runs SET reason='changed' WHERE id=$1", [run.id]);
    await assert.rejects(resetAll(pool, backup.sha256), { code: "backup_mismatch" });
    const fresh = await exportRanking(pool);
    const receipt = await resetAll(pool, fresh.sha256);
    assert.deepEqual([receipt.deleted_seasons, receipt.deleted_runs, receipt.deleted_commands], [1,1,1]);
    assert.equal(receipt.accounts_and_saves_unchanged, true);
    assert.equal((await resetAll(pool, fresh.sha256)).already_reset, true);
    assert.notEqual(receipt.generation, generation);
    assert.deepEqual((await pool.query("SELECT revision,payload FROM qq_cloud_saves WHERE user_id=$1", [owner])).rows[0], { revision: 8, payload: { progress: "preserve", points: 99 } });
    assert.equal((await browser.profile()).user.username, "SeasonTester");
    for (const revision of [rules, { ...rules, ruleset: `infinite-${ruleRevision(rules.ruleset) + 1}` }]) assert.equal(await new RankingStore(pool, revision).ensureSeason(), null);
    await fixture.store.migrate(); assert.equal(await service.ensureSeason(), null);
    const board = await (await browser.request("/api/ranked/board")).json();
    assert.equal(board.next_season_number, 1); assert.deepEqual(board.entries, []);
    await assert.rejects(startSeason(pool, rules.ruleset, generation), { code: "generation_confirmation_required" });
    const restarted = await startSeason(pool, rules.ruleset, receipt.generation);
    assert.equal(restarted.season.id, "season-1");
    assert.equal((await browser.request(`/api/ranked/runs/${run.id}`)).status, 404);
    assert.equal((await service.start(owner, "balanced")).season_id, "season-1");
    await pause(pool); // End the test preparing, not by implicitly opening a production season.
  } finally { await fixture.close(); }
});
