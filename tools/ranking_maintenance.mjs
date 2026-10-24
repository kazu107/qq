import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('../', import.meta.url));
const [mode = 'inspect', id, rawScore] = process.argv.slice(2);
const app = process.env.QQ_HEROKU_APP || 'qq-web';
const cli = process.env.QQ_HEROKU_CLI || 'C:/Program Files/heroku/client/bin/run';
const bundled = join(dirname(cli), 'node.exe');
const executable = existsSync(bundled) ? bundled : process.execPath;
if (!/^[a-z][a-z0-9-]{2,29}$/.test(app)) throw new Error('invalid_app');
async function remote(command, prefix) {
  const { stdout } = await promisify(execFile)(executable, [cli, 'run', '--no-tty', '--exit-code', '--app', app, `node server/ranking/maintenance.js ${command}`], { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 180000 });
  const line = stdout.split(/\r?\n/).find(line => line.startsWith(prefix));
  if (!line) throw new Error('missing_remote_result');
  return line.slice(prefix.length);
}
try {
  if (mode === 'inspect') console.log(await remote('inspect', 'QQ_RANKED_MAINTENANCE '));
  else if (mode === 'backup-and-delete') {
    if (!/^[a-f0-9-]{36}$/i.test(id || '') || !/^\d+$/.test(rawScore || '') || !Number.isSafeInteger(Number(rawScore))) throw new Error('explicit_run_id_and_score_required');
    const envelope = JSON.parse(Buffer.from(await remote(`export-test-run ${id} ${rawScore}`, 'QQ_RANKED_BACKUP '), 'base64').toString('utf8'));
    if (envelope.data.run.id !== id || Number(envelope.data.run.result.total_score) !== Number(rawScore) || createHash('sha256').update(JSON.stringify(envelope.data)).digest('hex') !== envelope.sha256) throw new Error('invalid_backup');
    const directory = resolve(root, 'tools/.local/ranking-reset');
    await mkdir(directory, { recursive: true });
    const path = join(directory, `${new Date().toISOString().replace(/[:.]/g, '-')}-${id}.json`);
    await writeFile(path, JSON.stringify(envelope, null, 2), { flag: 'wx', mode: 0o600 });
    console.log('RANKED_TEST_BACKUP_SAVED', path, envelope.sha256);
    console.log(await remote(`delete-test-run ${id} ${rawScore} ${envelope.sha256}`, 'QQ_RANKED_MAINTENANCE '));
  } else throw new Error('invalid_mode');
} catch (error) {
  console.error('RANKED_MAINTENANCE_FAILED', error.code || (error.message?.match(/^[a-z_]+$/) ? error.message : 'remote_operation_failed'));
  process.exitCode = 1;
}
