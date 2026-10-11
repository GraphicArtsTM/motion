// Запускается из RENDER_WINDOWS.bat / render-mac.command / render-linux.sh.
// По умолчанию рендерит обе версии в 1920×1080, 60 fps. Аргументы передаются в render.mjs:
//   --only pro | --only remake      — только одна версия
//   --scale 2                       — 4K
//   --fps 30, --fast, --headed, --cpu — см. render.mjs
import { spawnSync, execSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const oi = argv.indexOf('--only');
const only = oi >= 0 ? argv.splice(oi, 2)[1] : null;
const versions = only ? [only] : ['pro', 'remake'];

console.log('\n  PlayStation 2 — современное интро');
console.log('  Версии: ' + versions.map(v => v === 'pro' ? "Director's Cut (26 с)" : 'Remake (20 с)').join(' + ') + '\n');
const t0 = Date.now();
for (const v of versions) {
  console.log(`\n=== ${v === 'pro' ? "Director's Cut" : 'Remake'} ===`);
  const r = spawnSync(process.execPath, [path.join(dir, 'render.mjs'), '--version', v, ...argv], { stdio: 'inherit', cwd: dir });
  if (r.status !== 0) { console.error('\nРендер прерван с ошибкой (код ' + r.status + ').'); process.exit(r.status || 1); }
}
console.log(`\nВсё готово за ${((Date.now() - t0) / 60000).toFixed(1)} мин. Видео лежат в папке out\\`);
try {
  if (process.platform === 'win32') execSync(`explorer "${path.join(dir, 'out')}"`);
  else if (process.platform === 'darwin') execSync(`open "${path.join(dir, 'out')}"`);
} catch {}
