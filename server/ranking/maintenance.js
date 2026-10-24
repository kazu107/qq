"use strict";
const { createHash } = require("node:crypto");
const { AccountStore } = require("../accounts/store");
const { fail } = require("./store");

function snapshotHash(data) { return createHash("sha256").update(JSON.stringify(data)).digest("hex"); }
async function inspect(pool) {
  const seasons = await pool.query("SELECT id,ruleset,starts_at,ends_at FROM qq_ranked_seasons ORDER BY starts_at,id");
  const counts = await pool.query("SELECT status,count(*) FROM qq_ranked_runs GROUP BY status ORDER BY status");
  const verified = await pool.query("SELECT id,season_id,result->>'total_score' AS score FROM qq_ranked_runs WHERE status='verified' ORDER BY created_at");
  return { seasons: seasons.rows, counts: counts.rows, verified: verified.rows };
}
async function snapshot(client, id, score) {
  if (!/^[0-9a-f-]{36}$/i.test(id) || !Number.isSafeInteger(score) || score < 0) fail("invalid_target");
  const count = await client.query("SELECT count(*) FROM qq_ranked_runs WHERE status='verified'");
  if (Number(count.rows[0].count) !== 1) fail("not_single_test_record");
  const result = await client.query("SELECT * FROM qq_ranked_runs WHERE id=$1", [id]);
  const run = result.rows[0];
  if (!run || run.status !== "verified" || Number(run.result?.total_score) !== score || !/^(?:infinite-\d+:)?\d{4}-\d{2}$/.test(run.season_id)) fail("target_mismatch");
  const commands = await client.query("SELECT sequence,command FROM qq_ranked_commands WHERE run_id=$1 ORDER BY sequence", [id]);
  const seasons = await client.query("SELECT * FROM qq_ranked_seasons WHERE id !~ '^season-[1-9][0-9]{0,8}$' ORDER BY id");
  return { format: 1, run, commands: commands.rows, seasons: seasons.rows };
}
async function exportTestRun(pool, id, score) {
  const data = await snapshot(pool, id, score);
  return { sha256: snapshotHash(data), data };
}
async function deleteTestRun(pool, id, score, backupHash) {
  if (!/^[a-f0-9]{64}$/.test(backupHash || "")) fail("backup_required");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("LOCK TABLE qq_ranked_runs IN SHARE ROW EXCLUSIVE MODE");
    const data = await snapshot(client, id, score);
    if (snapshotHash(data) !== backupHash) fail("backup_mismatch");
    const commands = await client.query("DELETE FROM qq_ranked_commands WHERE run_id=$1", [id]);
    const removed = await client.query("DELETE FROM qq_ranked_runs WHERE id=$1 RETURNING id", [id]);
    if (removed.rowCount !== 1) fail("target_mismatch");
    const seasons = await client.query("DELETE FROM qq_ranked_seasons s WHERE id !~ '^season-[1-9][0-9]{0,8}$' AND NOT EXISTS(SELECT 1 FROM qq_ranked_runs r WHERE r.season_id=s.id)");
    await client.query("COMMIT");
    return { deletedRun: id, deletedRecords: 1, deletedCommands: commands.rowCount, deletedEmptyLegacySeasons: seasons.rowCount };
  } catch (error) { await client.query("ROLLBACK"); throw error; }
  finally { client.release(); }
}
async function main() {
  const [mode = "inspect", id, rawScore, backupHash] = process.argv.slice(2);
  const store = new AccountStore(process.env);
  try {
    if (mode === "inspect") console.log("QQ_RANKED_MAINTENANCE " + JSON.stringify(await inspect(store.pool)));
    else if (mode === "export-test-run") console.log("QQ_RANKED_BACKUP " + Buffer.from(JSON.stringify(await exportTestRun(store.pool, id, Number(rawScore)))).toString("base64"));
    else if (mode === "delete-test-run") console.log("QQ_RANKED_MAINTENANCE " + JSON.stringify(await deleteTestRun(store.pool, id, Number(rawScore), backupHash)));
    else fail("invalid_mode");
  } finally { await store.close(); }
}
if (require.main === module) main().catch(error => { console.error("RANKED_MAINTENANCE_FAILED", error.code || error.name); process.exitCode = 1; });
module.exports = { inspect, exportTestRun, deleteTestRun, snapshotHash };
