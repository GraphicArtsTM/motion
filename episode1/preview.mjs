// Просмотр мультфильма в браузере со звуком: node preview.mjs → http://localhost:8080
import http from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exec } from 'node:child_process';

const dir = path.dirname(fileURLToPath(import.meta.url));
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.png': 'image/png', '.ttf': 'font/ttf', '.m4a': 'audio/mp4', '.wav': 'audio/wav', '.mp3': 'audio/mpeg' };
const port = +(process.argv[2] || 8080);
http.createServer((req, res) => {
  let p = path.join(dir, decodeURIComponent(req.url.split('?')[0]));
  if (p.endsWith(path.sep)) p = path.join(p, 'index.html');
  if (!p.startsWith(dir) || !existsSync(p) || statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': MIME[path.extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
}).listen(port, () => {
  const url = `http://localhost:${port}/`;
  console.log('Плеер: ' + url + '  (пробел — пауза, ←/→ — перемотка; Ctrl+C — выход)');
  exec((process.platform === 'win32' ? 'start ""' : process.platform === 'darwin' ? 'open' : 'xdg-open') + ' ' + url);
});
