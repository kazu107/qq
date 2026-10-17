"use strict";
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { createHash, randomUUID } = require("node:crypto");
const { spawn } = require("node:child_process");
const { rules, ticket } = require("./store");

class VerifierWorker {
  constructor(account, env = process.env) { this.account = account; this.env = env; this.busy = false; this.stopped = false; this.pack = null; }
  start() {
    if (this.env.AUTH_ENABLED !== "true" || this.env.RANKED_VERIFIER_ENABLED !== "true") return;
    this.timer = setInterval(() => this.tick().catch(() => {}), 5000); this.timer.unref();
  }
  stop() { this.stopped = true; clearInterval(this.timer); this.child?.kill(); }
  async runtime() {
    const executable = this.env.GODOT_VERIFIER_PATH || path.join(__dirname, "vendor", "godot");
    await fs.access(executable);
    if (this.env.QQ_RANKED_TEST_PACK && this.env.NODE_ENV === "test") return { executable, pack: this.env.QQ_RANKED_TEST_PACK };
    if (this.pack) return { executable, pack: this.pack };
    const response = await fetch("https://qq.kazu107.xyz/releases/current.json", { signal: AbortSignal.timeout(15000), cache: "no-store" });
    const manifest = await response.json();
    if (manifest.ranking_ruleset !== rules.ruleset || !/^https:\/\/qq\.kazu107\.xyz\/objects\/[a-f0-9]{64}\.pck$/.test(manifest.pck?.url || "") || !/^[a-f0-9]{64}$/.test(manifest.pck?.sha256 || "") || manifest.pck.size > 150000000) throw new Error("verifier_pack_unavailable");
    const directory = path.join(os.tmpdir(), "qq-ranked-packs");
    await fs.mkdir(directory, { recursive: true });
    const target = path.join(directory, manifest.pck.sha256 + ".pck");
    let buffer;
    try { buffer = await fs.readFile(target); } catch {}
    if (!buffer) {
      const packResponse = await fetch(manifest.pck.url, { signal: AbortSignal.timeout(120000) });
      if (!packResponse.ok) throw new Error("verifier_pack_unavailable");
      buffer = Buffer.from(await packResponse.arrayBuffer());
    }
    if (buffer.length !== manifest.pck.size || createHash("sha256").update(buffer).digest("hex") !== manifest.pck.sha256) throw new Error("verifier_pack_integrity");
    await fs.writeFile(target, buffer);
    this.pack = target;
    return { executable, pack: target };
  }
  async tick() {
    if (this.busy || this.stopped) return;
    this.busy = true;
    let pool, job, lease;
    try {
      pool = (await this.account.storage()).pool;
      const runtime = await this.runtime();
      await pool.query("UPDATE qq_ranked_runs SET status='unverified',reason='verification_retry_limit' WHERE status='verifying' AND lease_until<now() AND attempts>=3");
      lease = randomUUID();
      const result = await pool.query(`UPDATE qq_ranked_runs SET status='verifying',lease_until=now()+interval '3 minutes',locked_by=$1,attempts=attempts+1
        WHERE id=(SELECT id FROM qq_ranked_runs WHERE (status='pending' OR status='verifying' AND lease_until<now()) AND attempts<3
          ORDER BY finished_at FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *`, [lease]);
      job = result.rows[0];
      if (!job) return;
      if (job.ruleset !== rules.ruleset) { await this.complete(pool, job.id, lease, "unverified", null, "ruleset_unavailable"); return; }
      const commands = await pool.query("SELECT command FROM qq_ranked_commands WHERE run_id=$1 ORDER BY sequence", [job.id]);
      const response = await this.verify(runtime, { ticket: ticket(job), commands: commands.rows.map(row => row.command) });
      if (response.result && Number.isSafeInteger(response.result.total_score) && response.result.total_score >= 0 && response.result.ticks / 60 <= (new Date(job.finished_at) - new Date(job.created_at)) / 1000 + 30) await this.complete(pool, job.id, lease, "verified", response.result, null);
      else await this.complete(pool, job.id, lease, response.error === "verification_budget" ? "unverified" : "rejected", null, /^[a-z_]{1,60}$/.test(response.error || "") ? response.error : "invalid_record");
    } catch {
      if (pool && job) await this.complete(pool, job.id, lease, "unverified", null, "verification_unavailable").catch(() => {});
    } finally { this.busy = false; }
  }
  async complete(pool, id, lease, status, result, reason) {
    await pool.query("UPDATE qq_ranked_runs SET status=$3,result=$4,reason=$5,locked_by=null,lease_until=null,updated_at=now() WHERE id=$1 AND locked_by=$2", [id, lease, status, result, reason]);
  }
  async verify(runtime, payload) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), "qq-ranked-job-"));
    const input = path.join(directory, "input.json");
    try {
      await fs.writeFile(input, JSON.stringify(payload), { mode: 0o600 });
      return await new Promise((resolve, reject) => {
        // The replay process receives no database, OAuth or hosting credentials.
        const env = { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, HOME: directory, APPDATA: directory, USERPROFILE: directory, LANG: "C.UTF-8" };
        const child = spawn(runtime.executable, ["--headless", "--audio-driver", "Dummy", "--main-pack", runtime.pack, "res://scenes/ranking/Verifier.tscn", "--", input], { env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
        this.child = child;
        let output = "", size = 0;
        const timeout = setTimeout(() => child.kill(), 120000);
        child.stdout.on("data", chunk => { size += chunk.length; if (size > 1000000) child.kill(); else output += chunk.toString(); });
        child.stderr.on("data", () => {});
        child.on("error", reject);
        child.on("close", () => {
          clearTimeout(timeout); this.child = null;
          const match = output.split(/\r?\n/).findLast(line => line.startsWith("QQ_RANKED_RESULT "));
          if (!match) { reject(new Error("verifier_failed")); return; }
          try { resolve(JSON.parse(match.slice("QQ_RANKED_RESULT ".length))); } catch { reject(new Error("verifier_failed")); }
        });
      });
    } finally {
      await fs.unlink(input).catch(() => {});
      // Godot may create isolated user data. Keep cleanup confined to this fresh, owned scratch directory.
      if (path.dirname(directory) === os.tmpdir() && path.basename(directory).startsWith("qq-ranked-job-")) await fs.rm(directory, { recursive: true, force: true });
    }
  }
}
module.exports = { VerifierWorker };
