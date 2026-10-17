"use strict";
const fs = require("node:fs/promises");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

async function main() {
  if (process.platform !== "linux") return;
  const version = "4.6.2-stable", name = `Godot_v${version}_linux.x86_64.zip`, executable = name.slice(0, -4);
  const root = path.join(__dirname, "vendor");
  await fs.mkdir(root, { recursive: true });
  const release = await (await fetch(`https://api.github.com/repos/godotengine/godot-builds/releases/tags/${version}`, { signal: AbortSignal.timeout(30000), headers: { "User-Agent": "QueueQuest-build" } })).json();
  const asset = release.assets?.find(item => item.name === name);
  if (!asset || !/^sha256:[a-f0-9]{64}$/.test(asset.digest || "")) throw new Error("Official Godot asset digest is unavailable");
  const response = await fetch(asset.browser_download_url, { signal: AbortSignal.timeout(120000) });
  if (!response.ok) throw new Error("Godot runtime download failed");
  const zip = Buffer.from(await response.arrayBuffer());
  if (zip.length > 100000000 || "sha256:" + createHash("sha256").update(zip).digest("hex") !== asset.digest) throw new Error("Godot runtime digest mismatch");
  // Extract only the named executable; never apply archive paths to the filesystem.
  const archive = path.join(root, "godot.zip");
  await fs.writeFile(archive, zip);
  const { stdout: binary } = await promisify(execFile)("unzip", ["-p", archive, executable], { encoding: null, maxBuffer: 250000000, timeout: 30000 });
  await fs.writeFile(path.join(root, "godot"), binary, { mode: 0o755 });
  await fs.unlink(archive);
  console.log("RANKED_VERIFIER_RUNTIME_INSTALLED", version);
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { main };
