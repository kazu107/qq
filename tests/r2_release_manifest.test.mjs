import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { prepareR2Release } from "../tools/prepare_r2_release.mjs";

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
