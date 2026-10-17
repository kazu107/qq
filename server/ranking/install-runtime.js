"use strict";
const fs = require("node:fs/promises");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { inflateRawSync } = require("node:zlib");

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
  let cursor = zip.length - 22;
  while (cursor > zip.length - 65558 && zip.readUInt32LE(cursor) !== 0x06054b50) cursor--;
  let offset = zip.readUInt32LE(cursor + 16), binary;
  while (zip.readUInt32LE(offset) === 0x02014b50) {
    const size = zip.readUInt32LE(offset + 20), raw = zip.readUInt32LE(offset + 24);
    const filenameLength = zip.readUInt16LE(offset + 28), extra = zip.readUInt16LE(offset + 30), comment = zip.readUInt16LE(offset + 32);
    if (zip.subarray(offset + 46, offset + 46 + filenameLength).toString() === executable) {
      if (raw > 250000000) throw new Error("Godot executable exceeds bound");
      const local = zip.readUInt32LE(offset + 42), begin = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
      binary = zip.readUInt16LE(offset + 10) === 8 ? inflateRawSync(zip.subarray(begin, begin + size), { maxOutputLength: raw }) : zip.subarray(begin, begin + size);
      if (binary.length !== raw) throw new Error("Invalid Godot executable size");
      break;
    }
    offset += 46 + filenameLength + extra + comment;
  }
  if (!binary) throw new Error("Godot executable not found");
  await fs.writeFile(path.join(root, "godot"), binary, { mode: 0o755 });
  console.log("RANKED_VERIFIER_RUNTIME_INSTALLED", version);
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { main };
