import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.resolve(__dirname, '..', 'scripts', 'generate-all-icons.mjs');

const res = spawnSync(process.execPath, [scriptPath], { stdio: 'inherit' });
if (res.status !== 0) {
  process.exit(res.status ?? 1);
}