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
const DOWNLOAD_URL = arg('download', 'https://drive.google.com/file/d/1yYH7Snh3UoY9Y2zil_xmXvR9fVRlP0QB/view?usp=drive_link');
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

// CRC32 (IEEE, igual que Zlib.crc32 de Ruby) — lo usa el updater IN-GAME (Android/PC),
// que solo tiene Zlib disponible (no Digest::SHA256 garantizado en mkxp-z).
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(file) {
  const buf = fs.readFileSync(file);
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    // Ignorar bytes CR (0x0D): el HTTPLite de Android convierte CRLF->LF al
    // descargar archivos de TEXTO, asi que hacemos el CRC insensible a CR.
    // (Los binarios .rxdata bajan intactos, pero rara vez tienen CR suelto;
    //  ignorarlo tambien en ellos mantiene el CRC consistente en ambos lados.)
    if (buf[i] === 0x0D) continue;
    c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) >>> 0;
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
  const crc = crc32(abs);
  const size = fs.statSync(abs).size;
  totalBytes += size;
  copyTo(abs, path.join(filesDir, rel));
  manifest.files.push({ path: rel, sha, crc32: crc, size });
}
fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest));
console.log('manifest.json:', manifest.files.length, 'archivos,', (totalBytes / 1048576).toFixed(1), 'MB alojados en files/');

// --- manifest-lite.txt (lo consume el updater IN-GAME en Ruby) -------------
// Formato (sin JSON, para parsear facil en mkxp-z):
//   linea 1: version
//   linea 2: base URL de files/
//   resto  : "<crc32-decimal>\t<size>\t<ruta relativa>"  (TAB separa; las rutas
//            llevan espacios pero nunca tabs)
const liteLines = [manifest.version, manifest.base];
for (const f of manifest.files) liteLines.push(`${f.crc32}\t${f.size}\t${f.path}`);
fs.writeFileSync(path.join(OUT, 'manifest-lite.txt'), liteLines.join('\n') + '\n');
console.log('manifest-lite.txt:', manifest.files.length, 'archivos (CRC32 para updater in-game).');

// --- version.txt con CHANGELOG ACUMULADO por versiones ---------------------
// El changelog se acumula en changelog-history.txt (fuente de verdad, mas nuevo
// arriba, en bloques "[vX]"). En version.txt se vuelca el historial completo, de
// modo que quien salte varias versiones (p.ej. 4.1.2 -> 4.1.4) vea TODAS las notas.
// El parser del juego (GameVersion.rb) lee CHANGELOG y sigue tomando lineas hasta
// una vacia o una con "=", asi que el historial NO puede llevar lineas vacias ni "=".
const HISTORY_FILE = path.join(OUT, 'changelog-history.txt');

// Notas de ESTA version (desde --changelog)
let notes = '';
if (CHANGELOG_FILE && fs.existsSync(CHANGELOG_FILE)) notes = fs.readFileSync(CHANGELOG_FILE, 'utf8').trim();

// Carga y parsea el historial existente en bloques { ver, lines }
const blocks = [];
if (fs.existsSync(HISTORY_FILE)) {
  let cur = null;
  for (const raw of fs.readFileSync(HISTORY_FILE, 'utf8').split(/\r?\n/)) {
    const m = raw.match(/^\[v([^\]]+)\]\s*$/);
    if (m) { cur = { ver: m[1], lines: [] }; blocks.push(cur); }
    else if (cur && raw.trim() !== '') cur.lines.push(raw.replace(/\s+$/, ''));
  }
}

// Si hay notas nuevas, coloca/reemplaza el bloque de esta version ARRIBA del todo
if (notes) {
  const noteLines = notes.split(/\r?\n/).filter(l => l.trim() !== '');
  const idx = blocks.findIndex(b => b.ver === VERSION);
  if (idx >= 0) blocks.splice(idx, 1);
  blocks.unshift({ ver: VERSION, lines: noteLines });
}

// Reescribe el historial (legible, con cabeceras de version)
const historyOut = blocks.map(b => [`[v${b.ver}]`, ...b.lines].join('\n')).join('\n');
if (blocks.length) fs.writeFileSync(HISTORY_FILE, historyOut + '\n');

// version.txt: CHANGELOG = historial acumulado, saneado para el parser del juego
const changelogSafe = blocks
  .flatMap(b => [`[v${b.ver}]`, ...b.lines])
  .filter(l => l.trim() !== '' && !l.includes('='))
  .join('\n');

const vlines = [
  `GAME_VERSION=${VERSION}`,
  `FORCE_UPDATE=false`,
  `DOWNLOAD_URL=${DOWNLOAD_URL}`,
];
if (changelogSafe) vlines.push(`CHANGELOG=${changelogSafe}`);
fs.writeFileSync(path.join(OUT, 'version.txt'), vlines.join('\n') + '\n');
console.log('version.txt generado (GAME_VERSION=' + VERSION + ', changelog acumulado: ' + blocks.length + ' version(es))');
console.log('\nListo. Ahora: commit + push del repo anil-game-updater y crea/actualiza el release si hace falta.');
