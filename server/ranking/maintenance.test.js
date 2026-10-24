"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { accountFixture, BrowserSession, testDatabaseEnv } = require("../../tests/helpers/account_fixture");
const { RankingStore, rules } = require("./store");
const { exportTestRun, deleteTestRun } = require("./maintenance");

test("test-run cleanup requires an exact backed-up legacy record and preserves account/save/current season", { skip: !testDatabaseEnv() }, async () => {
  const fixture = await accountFixture();
  try {
    const { pool } = fixture.store;
    const browser = new BrowserSession(fixture.origin);
    await browser.login();
    await browser.write("/api/account/username", { username: "CleanupUser" });
    const owner = (await browser.profile()).user.id;
    await pool.query("INSERT INTO qq_cloud_saves(user_id,revision,payload) VALUES($1,7,$2)", [owner, { progress: "keep", points: 77 }]);
    const season = await new RankingStore(pool).ensureSeason();
    await pool.query("INSERT INTO qq_ranked_seasons(id,ruleset,starts_at,ends_at) VALUES('infinite-2:2026-10','infinite-2',now()-interval '1 month',now())");
    const id = randomUUID();
    await pool.query("INSERT INTO qq_ranked_runs(id,user_id,season_id,ruleset,seed,starter_id,status,result) VALUES($1,$2,'infinite-2:2026-10','infinite-2',1,'balanced','verified',$3)", [id, owner, { total_score: 4300 }]);
    await pool.query("INSERT INTO qq_ranked_commands(run_id,sequence,command) VALUES($1,0,$2)", [id, { kind: "start" }]);
    await assert.rejects(exportTestRun(pool, id, 999), { code: "target_mismatch" });
    const backup = await exportTestRun(pool, id, 4300);
    assert.equal(backup.data.commands.length, 1);
    await assert.rejects(deleteTestRun(pool, id, 4300, "0".repeat(64)), { code: "backup_mismatch" });
    assert.equal((await pool.query("SELECT count(*) FROM qq_ranked_runs WHERE id=$1", [id])).rows[0].count, "1");
    const extra = await new RankingStore(pool).start(owner, "balanced");
    await pool.query("UPDATE qq_ranked_runs SET status='verified',result=$2 WHERE id=$1", [extra.id, { total_score: 10 }]);
    await assert.rejects(deleteTestRun(pool, id, 4300, backup.sha256), { code: "not_single_test_record" });
    await pool.query("UPDATE qq_ranked_runs SET status='active' WHERE id=$1", [extra.id]);
    const result = await deleteTestRun(pool, id, 4300, backup.sha256);
    assert.equal(result.deletedRecords, 1);
    assert.equal(result.deletedCommands, 1);
    assert.equal((await pool.query("SELECT count(*) FROM qq_ranked_runs WHERE id=$1", [extra.id])).rows[0].count, "1");
    assert.equal((await pool.query("SELECT id FROM qq_ranked_seasons")).rows[0].id, season.id);
    assert.equal((await pool.query("SELECT username FROM qq_accounts_users WHERE id=$1", [owner])).rows[0].username, "CleanupUser");
    assert.deepEqual((await pool.query("SELECT revision,payload FROM qq_cloud_saves WHERE user_id=$1", [owner])).rows[0], { revision: 7, payload: { points: 77, progress: "keep" } });
    await assert.rejects(exportTestRun(pool, extra.id, 10), { code: "not_single_test_record" });
    assert(/^infinite-\d+$/.test(rules.ruleset));
  } finally { await fixture.close(); }
});
