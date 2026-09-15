'use strict';
/*
 * AnilUpdater — actualizador de DELTAS del juego Pokémon Añil (Online Edition).
 *
 * Lo lanza el propio juego (PokemonEssentialsGameUpdater -> IO.popen(UPDATER_FILENAME))
 * cuando hay versión nueva, justo antes de cerrarse. Este programa:
 *   1. Descarga manifest.json del repo oficial (anil-game-updater).
 *   2. Compara el hash SHA-256 de cada archivo con el local del jugador.
 *   3. Descarga SOLO los que cambian, verifica su hash y los reemplaza.
 *   4. Reabre Game.exe.
 *
 * Se instala en  <juego>/poke_updater/anil_updater.exe  (junto al Game.exe del jugador).
 * No necesita token ni credenciales: descarga archivos públicos por HTTPS.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');
const { spawn } = require('child_process');

const RAW = process.env.ANIL_UPDATER_RAW || 'https://raw.githubusercontent.com/SukenFuyumi/anil-game-updater/main';
const MANIFEST_URL = RAW + '/manifest.json';

// Carpeta del juego = carpeta padre del .exe (el .exe vive en <juego>/poke_updater/).
const EXE_DIR = path.dirname(process.execPath);
const GAME_DIR = path.resolve(EXE_DIR, '..');

function log(msg) { process.stdout.write(msg + '\n'); }
function sha256(buf) { return crypto.createHash('sha256').update(buf).digest('hex'); }

// GET a Buffer, siguiendo redirecciones (GitHub raw a veces redirige).
function get(url, redirects = 0) {
  return new Promise((resolve, reject) => {
    if (redirects > 5) return reject(new Error('Demasiadas redirecciones'));
    https.get(url, { headers: { 'User-Agent': 'AnilUpdater' } }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        const next = res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).href;
        return resolve(get(next, redirects + 1));
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode + ' en ' + url)); }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
  });
}

function localSha(rel) {
  const abs = path.join(GAME_DIR, rel);
  try { return sha256(fs.readFileSync(abs)); } catch (e) { return null; }
}

function writeFileAtomic(rel, buf) {
  const abs = path.join(GAME_DIR, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  const tmp = abs + '.anilupd.tmp';
  fs.writeFileSync(tmp, buf);
  fs.renameSync(tmp, abs);   // reemplazo atómico
}

function launchGame() {
  const exe = path.join(GAME_DIR, 'Game.exe');
  if (!fs.existsSync(exe)) { log('No encuentro Game.exe; ábrelo manualmente.'); return; }
  try {
    const child = spawn(exe, [], { cwd: GAME_DIR, detached: true, stdio: 'ignore' });
    child.unref();
  } catch (e) { log('No pude reabrir el juego: ' + e.message); }
}

function pause(sec) { return new Promise(r => setTimeout(r, sec * 1000)); }

(async () => {
  log('=============================================');
  log('  AnilUpdater — actualizando Pokémon Añil');
  log('=============================================');
  log('Carpeta del juego: ' + GAME_DIR + '\n');
  let manifest;
  try {
    manifest = JSON.parse((await get(MANIFEST_URL)).toString('utf8'));
  } catch (e) {
    log('No pude obtener la lista de actualización (¿sin internet?).');
    log('Detalle: ' + e.message);
    log('\nAbriendo el juego sin actualizar...');
    await pause(3); launchGame(); return;
  }
  const base = manifest.base || (RAW + '/files');
  const changed = manifest.files.filter(f => localSha(f.path) !== f.sha);
  if (changed.length === 0) {
    log('El juego ya está al día (v' + manifest.version + ').');
    await pause(1.5); launchGame(); return;
  }
  const totalMB = (changed.reduce((a, f) => a + (f.size || 0), 0) / 1048576).toFixed(1);
  log('Versión ' + manifest.version + ': ' + changed.length + ' archivo(s) a actualizar (' + totalMB + ' MB).\n');

  let done = 0, failed = 0;
  for (const f of changed) {
    done++;
    const label = `[${done}/${changed.length}] ${f.path}`;
    try {
      const buf = await get(base + '/' + f.path.split('/').map(encodeURIComponent).join('/'));
      if (sha256(buf) !== f.sha) throw new Error('hash no coincide (descarga corrupta)');
      writeFileAtomic(f.path, buf);
      log('  OK  ' + label);
    } catch (e) {
      failed++;
      log('  ERROR ' + label + ' -> ' + e.message);
    }
  }
  log('');
  if (failed > 0) {
    log('Terminado con ' + failed + ' error(es). Vuelve a intentarlo más tarde si algo falló.');
  } else {
    log('¡Actualización completada a la v' + manifest.version + '!');
  }
  log('Abriendo el juego...');
  await pause(2.5);
  launchGame();
})();
