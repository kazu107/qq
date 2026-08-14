import { createReadStream } from "node:fs";
import { mkdtemp, mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const RELEASE_PREFIX = "releases/";
const CURRENT_MANIFEST_KEY = "releases/current.json";
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const COMMIT_PATTERN = /^[A-Za-z0-9._-]{1,80}$/;

function parseArguments(argv) {
  const options = new Map();
  const flags = new Set(["prune", "dry-run"]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) {
      throw new Error(`Invalid argument '${argument}'.`);
    }
    const name = argument.slice(2);
    if (flags.has(name)) {
      options.set(name, "true");
      continue;
    }
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`Missing value for --${name}.`);
    }
    options.set(name, value);
    index += 1;
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

function normalizeEndpoint(value) {
  const endpoint = new URL(value);
  if (endpoint.protocol !== "https:") {
    throw new Error("The R2 endpoint must use HTTPS.");
  }
  return endpoint.toString().replace(/\/$/, "");
}

function normalizeRelease(key, manifest) {
  if (!key.startsWith(RELEASE_PREFIX) || key === CURRENT_MANIFEST_KEY) {
    throw new Error(`Invalid release manifest key: ${key}`);
  }
  const commit = String(manifest?.commit ?? "").trim();
  const publishedAt = String(manifest?.published_at ?? "").trim();
  const pck = manifest?.pck;
  const sha256 = String(pck?.sha256 ?? "").toLowerCase();
  const objectKey = String(pck?.key ?? "").trim();
  const size = Number(pck?.size ?? 0);
  if (!COMMIT_PATTERN.test(commit)) {
    throw new Error(`Release ${key} has an invalid commit.`);
  }
  if (!Number.isFinite(Date.parse(publishedAt))) {
    throw new Error(`Release ${key} has an invalid published_at value.`);
  }
  if (!SHA256_PATTERN.test(sha256) || objectKey !== `objects/${sha256}.pck`) {
    throw new Error(`Release ${key} has inconsistent PCK metadata.`);
  }
  if (!Number.isSafeInteger(size) || size <= 0) {
    throw new Error(`Release ${key} has an invalid PCK size.`);
  }
  return {
    key,
    commit,
    publishedAt,
    timestamp: Date.parse(publishedAt),
    objectKey,
    sha256,
    size,
    manifest,
  };
}

function normalizeCurrent(manifest) {
  return {
    ...normalizeRelease(`releases/${String(manifest?.commit ?? "current")}.json`, manifest),
    key: CURRENT_MANIFEST_KEY,
  };
}

export function buildRetentionPlan({ releaseManifests, currentManifest, keep = 3 }) {
  if (!Number.isInteger(keep) || keep < 1) {
    throw new Error("keep must be a positive integer.");
  }
  const releases = releaseManifests
    .map(({ key, manifest }) => normalizeRelease(key, manifest))
    .sort((left, right) => right.timestamp - left.timestamp || right.commit.localeCompare(left.commit));
  const current = normalizeCurrent(currentManifest);
  const currentRelease = releases.find((release) => release.commit === current.commit)
    ?? releases.find((release) => release.objectKey === current.objectKey)
    ?? current;

  const retained = [currentRelease];
  for (const release of releases) {
    if (retained.length >= keep) {
      break;
    }
    if (!retained.some((candidate) => candidate.key === release.key)) {
      retained.push(release);
    }
  }

  const retainedKeys = new Set(retained.map((release) => release.key));
  const retainedObjectKeys = new Set(retained.map((release) => release.objectKey));
  retainedObjectKeys.add(current.objectKey);
  const archived = releases.filter((release) => !retainedKeys.has(release.key));
  const prunableObjectKeys = [...new Set(
    archived
      .map((release) => release.objectKey)
      .filter((objectKey) => !retainedObjectKeys.has(objectKey)),
  )].sort();

  return {
    current,
    retained,
    archived,
    prunableObjectKeys,
  };
}

function runAws(context, args) {
  const commonArgs = ["--endpoint-url", context.endpoint];
  if (context.profile) {
    commonArgs.push("--profile", context.profile);
  }
  const result = spawnSync("aws", [...args, ...commonArgs], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    windowsHide: true,
  });
  if (result.error) {
    throw new Error(`Could not run AWS CLI: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`AWS CLI failed (${result.status}): ${result.stderr || result.stdout}`.trim());
  }
  return result.stdout;
}

async function listObjectKeys(context, prefix) {
  const keys = [];
  let continuationToken = "";
  do {
    const args = [
      "s3api", "list-objects-v2",
      "--bucket", context.bucket,
      "--prefix", prefix,
      "--output", "json",
    ];
    if (continuationToken) {
      args.push("--continuation-token", continuationToken);
    }
    const page = JSON.parse(runAws(context, args) || "{}");
    for (const item of page.Contents ?? []) {
      const key = String(item.Key ?? "");
      if (key) {
        keys.push(key);
      }
    }
    continuationToken = page.IsTruncated ? String(page.NextContinuationToken ?? "") : "";
  } while (continuationToken);
  return keys;
}

function safeTempName(key) {
  return key.replace(/[^A-Za-z0-9._-]/g, "_");
}

async function downloadObject(context, key, destination) {
  await mkdir(path.dirname(destination), { recursive: true });
  runAws(context, [
    "s3api", "get-object",
    "--bucket", context.bucket,
    "--key", key,
    destination,
    "--output", "json",
  ]);
}

async function readRemoteManifest(context, key, temporaryDirectory) {
  const destination = path.join(temporaryDirectory, safeTempName(key));
  await downloadObject(context, key, destination);
  return JSON.parse(await readFile(destination, "utf8"));
}

async function sha256File(filePath) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk);
  }
  return hash.digest("hex");
}

async function validatePck(filePath, release) {
  try {
    const details = await stat(filePath);
    if (!details.isFile() || details.size !== release.size) {
      return false;
    }
    return await sha256File(filePath) === release.sha256;
  } catch (error) {
    if (error?.code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

async function writeAtomically(destination, contents) {
  await mkdir(path.dirname(destination), { recursive: true });
  const temporary = `${destination}.part`;
  await writeFile(temporary, contents);
  await rename(temporary, destination);
}

async function readOptionalJson(filePath, fallback) {
  try {
    return JSON.parse(await readFile(filePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") {
      return fallback;
    }
    throw error;
  }
}

export function mergeArchiveEntries(previousEntries, newEntries) {
  const entriesByCommit = new Map();
  for (const entry of [...previousEntries, ...newEntries]) {
    const commit = String(entry?.commit ?? "");
    if (COMMIT_PATTERN.test(commit)) {
      entriesByCommit.set(commit, entry);
    }
  }
  return [...entriesByCommit.values()].sort((left, right) =>
    Date.parse(String(right.published_at ?? "")) - Date.parse(String(left.published_at ?? ""))
      || String(right.commit).localeCompare(String(left.commit))
  );
}

async function archiveRelease(context, release) {
  const manifestPath = path.join(context.archiveRoot, "releases", `${release.commit}.json`);
  const pckPath = path.join(context.archiveRoot, "objects", `${release.sha256}.pck`);
  if (context.dryRun) {
    return { manifestPath, pckPath, verified: false, dryRun: true };
  }

  await writeAtomically(manifestPath, `${JSON.stringify(release.manifest, null, 2)}\n`);
  if (!await validatePck(pckPath, release)) {
    const partialPath = `${pckPath}.part`;
    await rm(partialPath, { force: true });
    await downloadObject(context, release.objectKey, partialPath);
    if (!await validatePck(partialPath, release)) {
      await rm(partialPath, { force: true });
      throw new Error(`Downloaded PCK failed verification: ${release.objectKey}`);
    }
    await mkdir(path.dirname(pckPath), { recursive: true });
    await rm(pckPath, { force: true });
    await rename(partialPath, pckPath);
  }
  if (!await validatePck(pckPath, release)) {
    throw new Error(`Local PCK archive is not valid: ${pckPath}`);
  }
  return { manifestPath, pckPath, verified: true, dryRun: false };
}

function deleteObject(context, key) {
  runAws(context, [
    "s3api", "delete-object",
    "--bucket", context.bucket,
    "--key", key,
    "--output", "json",
  ]);
}

async function executeRetention(context) {
  const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "qq-r2-retention-"));
  try {
    const releaseKeys = (await listObjectKeys(context, RELEASE_PREFIX))
      .filter((key) => key !== CURRENT_MANIFEST_KEY && key.endsWith(".json"));
    const [currentManifest, releaseManifests] = await Promise.all([
      readRemoteManifest(context, CURRENT_MANIFEST_KEY, temporaryDirectory),
      Promise.all(releaseKeys.map(async (key) => ({
        key,
        manifest: await readRemoteManifest(context, key, temporaryDirectory),
      }))),
    ]);
    const plan = buildRetentionPlan({
      releaseManifests,
      currentManifest,
      keep: context.keep,
    });

    process.stdout.write(`Current: ${plan.current.commit}\n`);
    process.stdout.write(`Retain in R2 (${plan.retained.length}): ${plan.retained.map((item) => item.commit).join(", ") || "none"}\n`);
    process.stdout.write(`Archive locally (${plan.archived.length}): ${plan.archived.map((item) => item.commit).join(", ") || "none"}\n`);
    process.stdout.write(`Prunable PCK objects: ${plan.prunableObjectKeys.length}\n`);

    const archiveResults = [];
    for (const release of plan.archived) {
      process.stdout.write(`${context.dryRun ? "Would archive" : "Archiving"} ${release.commit} (${release.size} bytes)\n`);
      archiveResults.push({
        release,
        result: await archiveRelease(context, release),
      });
    }

    if (!context.dryRun) {
      const indexPath = path.join(context.archiveRoot, "archive-index.json");
      const previousIndex = await readOptionalJson(indexPath, {});
      const newArchiveEntries = archiveResults.map(({ release, result }) => ({
        commit: release.commit,
        published_at: release.publishedAt,
        manifest: path.relative(context.archiveRoot, result.manifestPath),
        pck: path.relative(context.archiveRoot, result.pckPath),
        size: release.size,
        sha256: release.sha256,
        verified: result.verified,
      }));
      const index = {
        schema_version: 1,
        updated_at: new Date().toISOString(),
        bucket: context.bucket,
        endpoint: context.endpoint,
        keep_count: context.keep,
        current: plan.current.commit,
        retained_in_r2: plan.retained.map((release) => ({
          commit: release.commit,
          published_at: release.publishedAt,
          pck: release.objectKey,
        })),
        archived_locally: mergeArchiveEntries(
          Array.isArray(previousIndex.archived_locally) ? previousIndex.archived_locally : [],
          newArchiveEntries,
        ),
      };
      await writeAtomically(
        indexPath,
        `${JSON.stringify(index, null, 2)}\n`,
      );
    }

    if (context.prune && !context.dryRun) {
      if (archiveResults.some(({ result }) => !result.verified)) {
        throw new Error("R2 prune refused because one or more local archives were not verified.");
      }
      for (const release of plan.archived) {
        process.stdout.write(`Deleting old manifest ${release.key}\n`);
        deleteObject(context, release.key);
      }
      for (const objectKey of plan.prunableObjectKeys) {
        const archivedCopy = archiveResults.find(({ release }) => release.objectKey === objectKey);
        if (!archivedCopy?.result.verified) {
          throw new Error(`R2 prune refused because ${objectKey} has no verified local copy.`);
        }
        process.stdout.write(`Deleting archived PCK ${objectKey}\n`);
        deleteObject(context, objectKey);
      }
    } else if (plan.archived.length > 0) {
      process.stdout.write("R2 objects were not deleted. Run again with --prune after reviewing the archive.\n");
    }
    return plan;
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const keep = Number.parseInt(options.get("keep") ?? "3", 10);
  const dryRun = options.get("dry-run") === "true";
  const prune = options.get("prune") === "true";
  if (dryRun && prune) {
    throw new Error("--dry-run and --prune cannot be used together.");
  }
  const context = {
    bucket: requireOption(options, "bucket"),
    endpoint: normalizeEndpoint(requireOption(options, "endpoint")),
    archiveRoot: path.resolve(requireOption(options, "archive-root")),
    profile: options.get("profile")?.trim() ?? "",
    keep,
    dryRun,
    prune,
  };
  if (!Number.isInteger(keep) || keep < 1) {
    throw new Error("--keep must be a positive integer.");
  }
  await executeRetention(context);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  });
}
