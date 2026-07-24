import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.dirname(scriptDir);
const audioRoot = path.join(repoRoot, "assets", "audio", "sfx");
const catalog = JSON.parse(fs.readFileSync(path.join(repoRoot, "data", "sfx_catalog.json"), "utf8"));
const cards = JSON.parse(fs.readFileSync(path.join(repoRoot, "data", "cards.json"), "utf8"));
const relics = JSON.parse(fs.readFileSync(path.join(repoRoot, "data", "relics.json"), "utf8"));
const audioManagerSource = fs.readFileSync(path.join(repoRoot, "src", "autoload", "AudioManager.gd"), "utf8");
const requiredNonVocalDerivations = new Map([
  ["online_room_join", "map_select"],
  ["online_room_leave", "online_room_join"],
  ["online_connected", "ui_save"],
  ["online_reconnected", "online_connected"],
]);

const expectedIds = [
  ...catalog.map((entry) => entry.id),
  ...cards.map((card) => `card_${card.id}`),
  ...relics.map((relic) => `relic_${relic.id}`),
];
const errors = [];
const seen = new Set();
let minimumDuration = Number.POSITIVE_INFINITY;
let maximumDuration = 0;
let minimumRmsDb = Number.POSITIVE_INFINITY;
let maximumRmsDb = Number.NEGATIVE_INFINITY;
let maximumPeakDb = Number.NEGATIVE_INFINITY;
const rmsDbValues = [];

if (catalog.length !== 124) {
  errors.push(`Expected 124 shared catalog entries, got ${catalog.length}`);
}
const sharedIds = new Set(catalog.map((entry) => entry.id));
for (const entry of catalog) {
  if (!entry.category || !entry.name_ja || !entry.name_en) {
    errors.push(`${entry.id}: incomplete catalog metadata`);
  }
  if (entry.source && !sharedIds.has(entry.source)) {
    errors.push(`${entry.id}: unknown derived source ${entry.source}`);
  }
  if (!entry.source && (!entry.prompt || !Number.isInteger(entry.seed))) {
    errors.push(`${entry.id}: model-generated entry requires prompt and integer seed`);
  }
}
for (const [id, expectedSource] of requiredNonVocalDerivations) {
  const entry = catalog.find((candidate) => candidate.id === id);
  if (!entry || entry.source !== expectedSource || entry.prompt) {
    errors.push(`${id}: must remain a deterministic non-vocal derivative of ${expectedSource}`);
  }
}
if (
  audioManagerSource.includes("_connect_button_hover") ||
  audioManagerSource.includes("_on_button_hovered") ||
  audioManagerSource.includes('play_sfx("ui_hover"') ||
  audioManagerSource.includes('play_sfx("map_hover"') ||
  audioManagerSource.includes('play_sfx("ui_tooltip"')
) {
  errors.push("AudioManager: automatic hover SFX playback must remain disabled");
}

for (const id of expectedIds) {
  if (!id || seen.has(id)) {
    errors.push(`Blank or duplicate SFX ID: ${id}`);
    continue;
  }
  seen.add(id);
  const wavPath = path.join(audioRoot, `${id}.wav`);
  if (!fs.existsSync(wavPath)) {
    errors.push(`Missing WAV: ${id}`);
    continue;
  }

  try {
    const metrics = inspectWav(wavPath);
    if (metrics.audioFormat !== 1) errors.push(`${id}: expected PCM format 1, got ${metrics.audioFormat}`);
    if (metrics.channels !== 1) errors.push(`${id}: expected mono, got ${metrics.channels} channels`);
    if (metrics.sampleRate !== 48000) errors.push(`${id}: expected 48000 Hz, got ${metrics.sampleRate}`);
    if (metrics.bitsPerSample !== 16) errors.push(`${id}: expected 16-bit PCM, got ${metrics.bitsPerSample}`);
    if (metrics.duration < 0.18 || metrics.duration > 2.5) {
      errors.push(`${id}: suspicious duration ${metrics.duration.toFixed(3)} s`);
    }
    if (metrics.peak < 64 || metrics.rms < 8) {
      errors.push(`${id}: silent or near-silent audio (peak=${metrics.peak}, rms=${metrics.rms.toFixed(2)})`);
    }
    const rmsDb = linearToDb(metrics.rms / 32768);
    const peakDb = linearToDb(metrics.peak / 32768);
    if (rmsDb < -25.0 || rmsDb > -17.25) {
      errors.push(`${id}: normalized RMS is out of range (${rmsDb.toFixed(2)} dBFS)`);
    }
    if (peakDb > -1.25) {
      errors.push(`${id}: normalized peak is too high (${peakDb.toFixed(2)} dBFS)`);
    }
    minimumDuration = Math.min(minimumDuration, metrics.duration);
    maximumDuration = Math.max(maximumDuration, metrics.duration);
    minimumRmsDb = Math.min(minimumRmsDb, rmsDb);
    maximumRmsDb = Math.max(maximumRmsDb, rmsDb);
    maximumPeakDb = Math.max(maximumPeakDb, peakDb);
    rmsDbValues.push(rmsDb);
  } catch (error) {
    errors.push(`${id}: ${error.message}`);
  }
}

rmsDbValues.sort((a, b) => a - b);
const fifthPercentileRmsDb = percentile(rmsDbValues, 0.05);
const ninetyFifthPercentileRmsDb = percentile(rmsDbValues, 0.95);
if (ninetyFifthPercentileRmsDb - fifthPercentileRmsDb > 5.0) {
  errors.push(
    `SFX loudness spread is too wide: p05=${fifthPercentileRmsDb.toFixed(2)} dBFS, ` +
      `p95=${ninetyFifthPercentileRmsDb.toFixed(2)} dBFS`,
  );
}

if (errors.length > 0) {
  for (const error of errors) console.error(error);
  process.exit(1);
}

console.log(
  `SFX validation passed: ${expectedIds.length} WAV files, ` +
    `${minimumDuration.toFixed(2)}-${maximumDuration.toFixed(2)} s, ` +
    `RMS ${minimumRmsDb.toFixed(2)}..${maximumRmsDb.toFixed(2)} dBFS, ` +
    `p05/p95 ${fifthPercentileRmsDb.toFixed(2)}/${ninetyFifthPercentileRmsDb.toFixed(2)} dBFS, ` +
    `maximum peak ${maximumPeakDb.toFixed(2)} dBFS`,
);

function inspectWav(wavPath) {
  const buffer = fs.readFileSync(wavPath);
  if (buffer.length < 44 || buffer.toString("ascii", 0, 4) !== "RIFF" || buffer.toString("ascii", 8, 12) !== "WAVE") {
    throw new Error("invalid RIFF/WAVE header");
  }

  let offset = 12;
  let format = null;
  let dataOffset = -1;
  let dataLength = 0;
  while (offset + 8 <= buffer.length) {
    const chunkId = buffer.toString("ascii", offset, offset + 4);
    const chunkLength = buffer.readUInt32LE(offset + 4);
    const chunkDataOffset = offset + 8;
    if (chunkDataOffset + chunkLength > buffer.length) break;
    if (chunkId === "fmt " && chunkLength >= 16) {
      format = {
        audioFormat: buffer.readUInt16LE(chunkDataOffset),
        channels: buffer.readUInt16LE(chunkDataOffset + 2),
        sampleRate: buffer.readUInt32LE(chunkDataOffset + 4),
        bitsPerSample: buffer.readUInt16LE(chunkDataOffset + 14),
      };
    } else if (chunkId === "data") {
      dataOffset = chunkDataOffset;
      dataLength = chunkLength;
      break;
    }
    offset = chunkDataOffset + chunkLength + (chunkLength % 2);
  }

  if (format === null || dataOffset < 0 || dataLength <= 0) {
    throw new Error("missing fmt or data chunk");
  }
  if (format.bitsPerSample !== 16) {
    return { ...format, duration: 0, peak: 0, rms: 0 };
  }

  const sampleCount = Math.floor(dataLength / 2);
  let peak = 0;
  let squareSum = 0;
  for (let sampleIndex = 0; sampleIndex < sampleCount; sampleIndex += 1) {
    const sample = buffer.readInt16LE(dataOffset + sampleIndex * 2);
    const absolute = Math.abs(sample);
    peak = Math.max(peak, absolute);
    squareSum += sample * sample;
  }
  const duration = sampleCount / (format.sampleRate * format.channels);
  const rms = Math.sqrt(squareSum / Math.max(1, sampleCount));
  return { ...format, duration, peak, rms };
}

function linearToDb(value) {
  return 20 * Math.log10(Math.max(Number.EPSILON, value));
}

function percentile(values, ratio) {
  if (values.length === 0) return Number.NaN;
  return values[Math.floor((values.length - 1) * ratio)];
}
