// Новая серия из шаблона: node tools/new-episode.mjs 3 "Линия 0"
// → episodes/e03/ (episode.js, shots.js, dialogue.json, timeline.json, audio/cues.py, STORY.md) + запись в episodes/index.json.
// Дальше: пишем сценарий (STORY.md) и реплики (dialogue.json) → node tools/... → см. CLAUDE.md, раздел «Как сделать новую серию».
import { cpSync, existsSync, readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const [num, ...nameParts] = process.argv.slice(2);
const n = parseInt(num, 10), name = nameParts.join(' ').trim();
if (!n || !name) { console.log('использование: node tools/new-episode.mjs <номер> "<название>"'); process.exit(1); }
const id = 'e' + String(n).padStart(2, '0'), dir = path.join(root, 'episodes', id);
if (existsSync(dir)) { console.error(`серия ${id} уже есть: ${dir}`); process.exit(1); }
cpSync(path.join(root, 'episodes', '_template'), dir, { recursive: true });
const title = `Серия ${n} · ${name}`;
const fill = p => {
  for (const f of readdirSync(p)) {
    const q = path.join(p, f);
    if (statSync(q).isDirectory()) { fill(q); continue; }
    if (!/\.(js|json|md|py)$/.test(f)) continue;
    writeFileSync(q, readFileSync(q, 'utf8').replaceAll('__TITLE__', title).replaceAll('__N__', String(n)).replaceAll('__NAME__', name).replaceAll('__CAPS__', name.toUpperCase()));
  }
};
fill(dir);
const idxPath = path.join(root, 'episodes', 'index.json');
const idx = JSON.parse(readFileSync(idxPath, 'utf8'));
idx.episodes.push({ id, title, file: `PAUK_NOVOGRADA_S01E${String(n).padStart(2, '0')}` });
writeFileSync(idxPath, JSON.stringify(idx, null, 2) + '\n');
console.log(`✅ создана серия ${id}: ${dir}
  1. сценарий — ${id}/STORY.md, реплики — ${id}/dialogue.json (id, who, t, text, hint)
  2. голоса и звук — tools/audio.sh ${id}   (лист озвучки: python3 tools/voiceover.py ${id})
  3. шоты — ${id}/shots.js, проверка кадров: node render.mjs --ep ${id} --story --stills 5,20,35
  4. просмотр: node preview.mjs ${id}   ·   видео: node make-video.mjs --ep ${id}`);
