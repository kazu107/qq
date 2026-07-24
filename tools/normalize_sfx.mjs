import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const TARGET_RMS_DB = -18.0;
const MIN_OUTPUT_RMS_DB = -24.5;
const MAX_PEAK_DB = -1.5;
const MAX_GAIN_DB = 24.0;
const MIN_GAIN_DB = -24.0;
const SOFT_KNEE_RATIO = 0.8;
const MAX_NORMALIZATION_PASSES = 4;

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.dirname(scriptDir);
const audioRoot = path.join(repoRoot, "assets", "audio", "sfx");
const wavPaths = fs
  .readdirSync(audioRoot)
  .filter((fileName) => fileName.endsWith(".wav"))
  .map((fileName) => path.join(audioRoot, fileName))
  .sort();

if (wavPaths.length === 0) {
  throw new Error(`No WAV files found under ${audioRoot}`);
}

const summaries = [];
for (const wavPath of wavPaths) {
  summaries.push(normalizeWav(wavPath));
}

const rmsValues = summaries.map((entry) => entry.outputRmsDb).sort((a, b) => a - b);
const peakValues = summaries.map((entry) => entry.outputPeakDb).sort((a, b) => a - b);
console.log(
  `Normalized ${summaries.length} SFX: ` +
    `RMS ${rmsValues[0].toFixed(2)}..${rmsValues.at(-1).toFixed(2)} dBFS, ` +
    `peak ${peakValues[0].toFixed(2)}..${peakValues.at(-1).toFixed(2)} dBFS`,
);

function normalizeWav(wavPath) {
  const buffer = fs.readFileSync(wavPath);
  const wav = inspectWav(buffer);
  if (wav.audioFormat !== 1 || wav.channels !== 1 || wav.sampleRate !== 48000 || wav.bitsPerSample !== 16) {
    throw new Error(`${path.basename(wavPath)}: expected PCM 16-bit mono 48 kHz WAV`);
  }

  const input = measureSamples(buffer, wav.dataOffset, wav.dataLength);
  if (input.rms <= 0 || input.peak <= 0) {
    throw new Error(`${path.basename(wavPath)}: cannot normalize silent audio`);
  }

  const inputRmsDb = linearToDb(input.rms / 32768);
  const inputPeakDb = linearToDb(input.peak / 32768);
  if (
    inputRmsDb >= MIN_OUTPUT_RMS_DB &&
    inputRmsDb <= TARGET_RMS_DB + 0.25 &&
    inputPeakDb <= MAX_PEAK_DB + 0.05
  ) {
    return {
      id: path.basename(wavPath, ".wav"),
      gainDb: 0,
      outputRmsDb: inputRmsDb,
      outputPeakDb: inputPeakDb,
    };
  }

  const peakLimit = 10 ** (MAX_PEAK_DB / 20);
  const softKnee = peakLimit * SOFT_KNEE_RATIO;

  let outputBuffer = Buffer.from(buffer);
  let output = input;
  let totalGainDb = 0;
  for (let pass = 0; pass < MAX_NORMALIZATION_PASSES; pass += 1) {
    const currentRmsDb = linearToDb(output.rms / 32768);
    const gainDb = clamp(TARGET_RMS_DB - currentRmsDb, MIN_GAIN_DB, MAX_GAIN_DB);
    const gain = 10 ** (gainDb / 20);
    const inputBuffer = outputBuffer;
    outputBuffer = Buffer.from(inputBuffer);
    for (let offset = wav.dataOffset; offset < wav.dataOffset + wav.dataLength; offset += 2) {
      const sample = inputBuffer.readInt16LE(offset);
      const amplified = (sample / 32768) * gain;
      const limited = softLimit(amplified, softKnee, peakLimit);
      const normalized = clamp(Math.round(limited * 32768), -32768, 32767);
      outputBuffer.writeInt16LE(normalized, offset);
    }
    totalGainDb += gainDb;
    output = measureSamples(outputBuffer, wav.dataOffset, wav.dataLength);
    if (linearToDb(output.rms / 32768) >= MIN_OUTPUT_RMS_DB) {
      break;
    }
  }

  const temporaryPath = `${wavPath}.normalize.tmp`;
  fs.writeFileSync(temporaryPath, outputBuffer);
  fs.renameSync(temporaryPath, wavPath);

  return {
    id: path.basename(wavPath, ".wav"),
    gainDb: totalGainDb,
    outputRmsDb: linearToDb(output.rms / 32768),
    outputPeakDb: linearToDb(output.peak / 32768),
  };
}

function inspectWav(buffer) {
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
    if (chunkDataOffset + chunkLength > buffer.length) {
      break;
    }
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

  if (format === null || dataOffset < 0 || dataLength <= 0 || dataLength % 2 !== 0) {
    throw new Error("missing or invalid fmt/data chunk");
  }
  return { ...format, dataOffset, dataLength };
}

function measureSamples(buffer, dataOffset, dataLength) {
  let peak = 0;
  let squareSum = 0;
  const sampleCount = dataLength / 2;
  for (let offset = dataOffset; offset < dataOffset + dataLength; offset += 2) {
    const sample = buffer.readInt16LE(offset);
    peak = Math.max(peak, Math.abs(sample));
    squareSum += sample * sample;
  }
  return {
    peak,
    rms: Math.sqrt(squareSum / Math.max(1, sampleCount)),
  };
}

function linearToDb(value) {
  return 20 * Math.log10(Math.max(Number.EPSILON, value));
}

function softLimit(value, knee, limit) {
  const magnitude = Math.abs(value);
  if (magnitude <= knee) {
    return value;
  }
  const compressed = knee + (limit - knee) * Math.tanh((magnitude - knee) / (limit - knee));
  return Math.sign(value) * compressed;
}

function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value));
}
