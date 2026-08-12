import { createReadStream } from "node:fs";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { pathToFileURL } from "node:url";

const VERSION_PATTERN = /^QQ-\d+\.\d+\.\d+$/;
const COMMIT_PATTERN = /^[A-Za-z0-9._-]{1,80}$/;

function parseArguments(argv) {
  const options = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith("--") || value === undefined) {
      throw new Error(`Invalid argument near '${name ?? ""}'. Expected --name value.`);
    }
    options.set(name.slice(2), value);
  }
  return options;
}

function requireOption(options, name) {
  const value = options.get(name)?.trim();
  if (!value) {
    throw new Error(`Missing required option --${name}.`);
  }
  return value;
}

function normalizePublicBaseUrl(value) {
  const url = new URL(value);
  if (url.protocol !== "https:") {
    throw new Error("The R2 public base URL must use HTTPS.");
  }
  if (url.search || url.hash) {
    throw new Error("The R2 public base URL cannot contain a query or fragment.");
  }
  return url.toString().replace(/\/$/, "");
}

async function sha256File(filePath) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk);
  }
  return hash.digest("hex");
}

async function readGameVersion(versionFile) {
  const contents = await readFile(versionFile, "utf8");
  const data = JSON.parse(contents);
  const version = String(data.current_version ?? "").trim();
  if (!VERSION_PATTERN.test(version)) {
    throw new Error(`Invalid current_version in ${versionFile}.`);
  }
  return version;
}

function serializeEnvironment(values) {
  return Object.entries(values)
    .map(([name, value]) => {
      const text = String(value);
      if (/[\r\n]/.test(text)) {
        throw new Error(`Environment value ${name} contains a newline.`);
      }
      return `${name}=${text}`;
    })
    .join("\n") + "\n";
}

export async function prepareR2Release({
  pckPath,
  outputDirectory,
  publicBaseUrl,
  commit,
  versionFile,
  publishedAt = new Date().toISOString(),
}) {
  const normalizedCommit = String(commit).trim();
  if (!COMMIT_PATTERN.test(normalizedCommit)) {
    throw new Error("Commit must contain only letters, numbers, dots, underscores, or hyphens.");
  }

  const normalizedBaseUrl = normalizePublicBaseUrl(publicBaseUrl);
  const pckStats = await stat(pckPath);
  if (!pckStats.isFile() || pckStats.size <= 0) {
    throw new Error(`PCK is missing or empty: ${pckPath}`);
  }

  const [sha256, gameVersion] = await Promise.all([
    sha256File(pckPath),
    readGameVersion(versionFile),
  ]);
  const objectKey = `objects/${sha256}.pck`;
  const releaseManifestKey = `releases/${normalizedCommit}.json`;
  const currentManifestKey = "releases/current.json";
  const manifest = {
    schema_version: 1,
    game_version: gameVersion,
    commit: normalizedCommit,
    published_at: publishedAt,
    pck: {
      url: `${normalizedBaseUrl}/${objectKey}`,
      key: objectKey,
      size: pckStats.size,
      sha256,
    },
  };

  await mkdir(outputDirectory, { recursive: true });
  const serializedManifest = `${JSON.stringify(manifest, null, 2)}\n`;
  await Promise.all([
    writeFile(path.join(outputDirectory, "release.json"), serializedManifest, "utf8"),
    writeFile(path.join(outputDirectory, "current.json"), serializedManifest, "utf8"),
    writeFile(path.join(outputDirectory, "release.env"), serializeEnvironment({
      PCK_OBJECT_KEY: objectKey,
      RELEASE_MANIFEST_KEY: releaseManifestKey,
      CURRENT_MANIFEST_KEY: currentManifestKey,
      PCK_SHA256: sha256,
      PCK_SIZE: pckStats.size,
      GAME_VERSION: gameVersion,
    }), "utf8"),
  ]);

  return { manifest, objectKey, releaseManifestKey, currentManifestKey };
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const result = await prepareR2Release({
    pckPath: path.resolve(requireOption(options, "pck")),
    outputDirectory: path.resolve(requireOption(options, "output")),
    publicBaseUrl: requireOption(options, "public-base-url"),
    commit: requireOption(options, "commit"),
    versionFile: path.resolve(options.get("version-file") || "data/version_history.json"),
  });
  process.stdout.write(`${JSON.stringify(result.manifest)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}
