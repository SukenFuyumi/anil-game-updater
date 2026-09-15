'use strict';
/*
 * Generador de manifiesto + archivo de versión para el auto-updater del Añil.
 *
 * Recorre los archivos VIGILADOS del juego (Data/*.rxdata, Data/serverinfo.ini,
 * Plugins/**, pu_config), calcula su hash SHA-256, los COPIA a files/ (para hostearlos
 * en este repo) y genera:
 *   - manifest.json : { version, files: [ {path, sha, size} ] }
 *   - version.txt   : el archivo que consume el updater IN-GAME del juego
 *                     (GAME_VERSION, CHANGELOG multilínea, DOWNLOAD_URL)
 *
 * Uso (desde la raíz del repo anil-game-updater):
 *   node tools/gen-manifest.js --version 4.1.2 --changelog changelog.txt \
 *        [--game "E:/.../Pokemon Anil V4.13"] [--out .]
 *
 * changelog.txt: texto libre (multilínea) con las notas de la versión.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };

const GAME = arg('game', process.env.ANIL_GAME_DIR || 'E:/Pokemon Super añil randomlocke/Pokemon Anil V4.13');
const OUT = path.resolve(arg('out', '.'));                 // raíz del repo anil-game-updater
const VERSION = arg('version', null);
const CHANGELOG_FILE = arg('changelog', null);
// Descarga completa (primera instalación) — se muestra en el aviso in-game.
const DOWNLOAD_URL = arg('download', 'https://drive.google.com/');
const REPO_RAW = arg('raw', 'https://raw.githubusercontent.com/SukenFuyumi/anil-game-updater/main');

if (!VERSION) { console.error('Falta --version (ej. 4.1.2)'); process.exit(1); }

// --- Qué archivos vigilar --------------------------------------------------
// Rutas RELATIVAS a la carpeta del juego. Se hostean en files/<misma ruta>.
function listTracked(gameDir) {
  const out = [];
  const add = p => { const abs = path.join(gameDir, p); if (fs.existsSync(abs) && fs.statSync(abs).isFile()) out.push(p.replace(/\\/g, '/')); };
  // pu_config y archivos raíz de config
  ['pu_config', 'mkxp.json', 'Data/serverinfo.ini'].forEach(add);
  // Todos los Data/*.rxdata
  const dataDir = path.join(gameDir, 'Data');
  if (fs.existsSync(dataDir)) {
    fs.readdirSync(dataDir).filter(f => /\.rxdata$/i.test(f)).forEach(f => add('Data/' + f));
  }
  // Todo Plugins/** (recursivo)
  const walk = (rel) => {
    const abs = path.join(gameDir, rel);
    if (!fs.existsSync(abs)) return;
    for (const e of fs.readdirSync(abs)) {
      const r = rel + '/' + e;
      const a = path.join(gameDir, r);
      if (fs.statSync(a).isDirectory()) walk(r);
      else out.push(r.replace(/\\/g, '/'));
    }
  };
  walk('Plugins');
  return [...new Set(out)];
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function copyTo(src, destAbs) {
  fs.mkdirSync(path.dirname(destAbs), { recursive: true });
  fs.copyFileSync(src, destAbs);
}

const tracked = listTracked(GAME);
console.log('Archivos vigilados:', tracked.length);

const filesDir = path.join(OUT, 'files');
// Limpia files/ para no dejar restos de rutas que ya no existen.
fs.rmSync(filesDir, { recursive: true, force: true });

const manifest = { version: VERSION, generated: new Date().toISOString(), base: REPO_RAW + '/files', files: [] };
let totalBytes = 0;
for (const rel of tracked) {
  const abs = path.join(GAME, rel);
  const sha = sha256(abs);
  const size = fs.statSync(abs).size;
  totalBytes += size;
  copyTo(abs, path.join(filesDir, rel));
  manifest.files.push({ path: rel, sha, size });
}
fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest));
console.log('manifest.json:', manifest.files.length, 'archivos,', (totalBytes / 1048576).toFixed(1), 'MB alojados en files/');

// --- version.txt (lo consume el updater IN-GAME del juego) -----------------
let changelog = '';
if (CHANGELOG_FILE && fs.existsSync(CHANGELOG_FILE)) changelog = fs.readFileSync(CHANGELOG_FILE, 'utf8').trim();
// El parser del juego lee CHANGELOG y sigue leyendo líneas hasta una vacía o una con "=".
// Por eso el CHANGELOG va AL FINAL y sin líneas vacías intermedias.
const vlines = [
  `GAME_VERSION=${VERSION}`,
  `FORCE_UPDATE=false`,
  `DOWNLOAD_URL=${DOWNLOAD_URL}`,
];
if (changelog) {
  const safe = changelog.split(/\r?\n/).filter(l => l.trim() !== '' && !l.includes('=')).join('\n');
  vlines.push(`CHANGELOG=${safe}`);
}
fs.writeFileSync(path.join(OUT, 'version.txt'), vlines.join('\n') + '\n');
console.log('version.txt generado (GAME_VERSION=' + VERSION + (changelog ? ', con changelog' : '') + ')');
console.log('\nListo. Ahora: commit + push del repo anil-game-updater y crea/actualiza el release si hace falta.');
