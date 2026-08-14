import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { prepareR2Release } from "../tools/prepare_r2_release.mjs";
import { buildRetentionPlan, mergeArchiveEntries } from "../tools/archive_r2_releases.mjs";

const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

test("prepareR2Release creates content-addressed manifests and upload metadata", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "qq-r2-release-"));
  try {
    const pckPath = path.join(directory, "index.pck");
    const versionFile = path.join(directory, "version.json");
    const outputDirectory = path.join(directory, "output");
    const contents = Buffer.from("deterministic-pck-fixture");
    const expectedHash = createHash("sha256").update(contents).digest("hex");
    await writeFile(pckPath, contents);
    await writeFile(versionFile, JSON.stringify({ current_version: "QQ-1.2.3" }));

    const result = await prepareR2Release({
      pckPath,
      outputDirectory,
      publicBaseUrl: "https://qq.kazu107.xyz/",
      commit: "abc1234",
      versionFile,
      publishedAt: "2026-08-13T00:00:00.000Z",
    });

    assert.equal(result.objectKey, `objects/${expectedHash}.pck`);
    assert.equal(result.releaseManifestKey, "releases/abc1234.json");
    assert.equal(result.manifest.pck.url, `https://qq.kazu107.xyz/objects/${expectedHash}.pck`);
    assert.equal(result.manifest.pck.size, contents.length);
    assert.equal(result.manifest.game_version, "QQ-1.2.3");

    const current = JSON.parse(await readFile(path.join(outputDirectory, "current.json"), "utf8"));
    const release = JSON.parse(await readFile(path.join(outputDirectory, "release.json"), "utf8"));
    const environment = await readFile(path.join(outputDirectory, "release.env"), "utf8");
    assert.deepEqual(current, release);
    assert.equal(current.pck.sha256, expectedHash);
    assert.match(environment, new RegExp(`^PCK_OBJECT_KEY=objects/${expectedHash}\\.pck$`, "m"));
    assert.match(environment, /^CURRENT_MANIFEST_KEY=releases\/current\.json$/m);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("prepareR2Release rejects insecure public URLs", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "qq-r2-release-invalid-"));
  try {
    const pckPath = path.join(directory, "index.pck");
    const versionFile = path.join(directory, "version.json");
    await writeFile(pckPath, "pck");
    await writeFile(versionFile, JSON.stringify({ current_version: "QQ-1.0.0" }));
    await assert.rejects(
      prepareR2Release({
        pckPath,
        outputDirectory: path.join(directory, "output"),
        publicBaseUrl: "http://qq.kazu107.xyz",
        commit: "abc1234",
        versionFile,
      }),
      /must use HTTPS/
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("the Godot Web shell loads a validated R2 PCK while preserving local development", async () => {
  const shell = await readFile(path.join(PROJECT_ROOT, "web", "custom_shell.html"), "utf8");
  const preset = await readFile(path.join(PROJECT_ROOT, "export_presets.cfg"), "utf8");
  const workflow = await readFile(path.join(PROJECT_ROOT, ".github", "workflows", "publish-web-r2.yml"), "utf8");
  const gitignore = await readFile(path.join(PROJECT_ROOT, ".gitignore"), "utf8");
  assert.match(shell, /https:\/\/qq\.kazu107\.xyz\/releases\/current\.json/);
  assert.match(shell, /engine\.preloadFile\(pack\.source, LOCAL_PACK_PATH\)/);
  assert.match(shell, /engine\.start\(\{ args: \['--main-pack', LOCAL_PACK_PATH\]/);
  assert.match(shell, /\['localhost', '127\.0\.0\.1', '0\.0\.0\.0', '\[::1\]'\]/);
  assert.doesNotMatch(shell, /engine\.startGame\(/);
  assert.match(preset, /html\/custom_html_shell="res:\/\/web\/custom_shell\.html"/);
  assert.match(preset, /exclude_filter="[^"]*web\/\*/);
  assert.match(workflow, /aws s3api put-bucket-cors/);
  assert.match(workflow, /tr -d '\\r'.*grep -Fxiq/);
  assert.match(workflow, /assert_cors "\$manifest_url" manifest/);
  assert.match(workflow, /assert_cors "\$pck_url" pck/);
  assert.match(gitignore, /^\/build\/web\/index\.pck$/m);

  const inlineScripts = [...shell.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.equal(inlineScripts.length, 1);
  const syntaxCheck = inlineScripts[0][1]
    .replace("const GODOT_CONFIG = $GODOT_CONFIG;", "const GODOT_CONFIG = { executable: 'index', args: [], fileSizes: { 'index.pck': 1, 'index.wasm': 1 } };")
    .replace("const GODOT_THREADS_ENABLED = $GODOT_THREADS_ENABLED;", "const GODOT_THREADS_ENABLED = false;");
  assert.doesNotThrow(() => new Function(syntaxCheck));
});

function retentionManifest(commit, day, hash, size = 100) {
  return {
    schema_version: 1,
    game_version: "QQ-0.17.0",
    commit,
    published_at: `2026-08-${String(day).padStart(2, "0")}T00:00:00.000Z`,
    pck: {
      url: `https://qq.example.test/objects/${hash}.pck`,
      key: `objects/${hash}.pck`,
      size,
      sha256: hash,
    },
  };
}

test("R2 retention keeps current plus the newest releases and archives the rest", () => {
  const hashes = ["a", "b", "c", "d", "e"].map((letter) => letter.repeat(64));
  const releases = hashes.map((hash, index) => ({
    key: `releases/commit-${index + 1}.json`,
    manifest: retentionManifest(`commit-${index + 1}`, index + 1, hash),
  }));
  const plan = buildRetentionPlan({
    releaseManifests: releases,
    currentManifest: releases[3].manifest,
    keep: 3,
  });

  assert.deepEqual(plan.retained.map((release) => release.commit), ["commit-4", "commit-5", "commit-3"]);
  assert.deepEqual(plan.archived.map((release) => release.commit), ["commit-2", "commit-1"]);
  assert.deepEqual(plan.prunableObjectKeys, [`objects/${hashes[0]}.pck`, `objects/${hashes[1]}.pck`]);
});

test("R2 retention never prunes a PCK shared by a retained release", () => {
  const sharedHash = "f".repeat(64);
  const oldHash = "1".repeat(64);
  const releases = [
    { key: "releases/old.json", manifest: retentionManifest("old", 1, sharedHash) },
    { key: "releases/older.json", manifest: retentionManifest("older", 2, oldHash) },
    { key: "releases/new.json", manifest: retentionManifest("new", 3, sharedHash) },
  ];
  const plan = buildRetentionPlan({
    releaseManifests: releases,
    currentManifest: releases[2].manifest,
    keep: 1,
  });

  assert.deepEqual(plan.archived.map((release) => release.commit), ["older", "old"]);
  assert.deepEqual(plan.prunableObjectKeys, [`objects/${oldHash}.pck`]);
});

test("R2 retention reserves one of the three slots for current when its immutable manifest is missing", () => {
  const currentHash = "9".repeat(64);
  const releases = [1, 2, 3].map((day) => ({
    key: `releases/release-${day}.json`,
    manifest: retentionManifest(`release-${day}`, day, String(day).repeat(64)),
  }));
  const plan = buildRetentionPlan({
    releaseManifests: releases,
    currentManifest: retentionManifest("rollback-current", 1, currentHash),
    keep: 3,
  });

  assert.deepEqual(plan.retained.map((release) => release.commit), ["rollback-current", "release-3", "release-2"]);
  assert.deepEqual(plan.archived.map((release) => release.commit), ["release-1"]);
  assert.ok(!plan.prunableObjectKeys.includes(`objects/${currentHash}.pck`));
});

test("R2 retention rejects manifests whose object key does not match the hash", () => {
  const invalid = retentionManifest("invalid", 1, "a".repeat(64));
  invalid.pck.key = `objects/${"b".repeat(64)}.pck`;
  assert.throws(() => buildRetentionPlan({
    releaseManifests: [{ key: "releases/invalid.json", manifest: invalid }],
    currentManifest: invalid,
    keep: 3,
  }), /inconsistent PCK metadata/);
});

test("R2 local archive index keeps prior releases and updates duplicate commits", () => {
  const previous = [
    { commit: "old", published_at: "2026-08-01T00:00:00.000Z", verified: true },
    { commit: "same", published_at: "2026-08-02T00:00:00.000Z", verified: false },
  ];
  const incoming = [
    { commit: "same", published_at: "2026-08-02T00:00:00.000Z", verified: true },
    { commit: "new", published_at: "2026-08-03T00:00:00.000Z", verified: true },
  ];
  assert.deepEqual(mergeArchiveEntries(previous, incoming), [
    incoming[1],
    incoming[0],
    previous[0],
  ]);
});
