# anil-game-updater

Canal de **actualización del juego** Pokémon Añil — Online Edition (fork del grupo).

El juego ya trae el plugin `PokemonEssentialsGameUpdater`, que al abrir comprueba una URL de
versión y, si hay novedad, avisa **dentro del juego**, muestra el changelog y lanza un
actualizador externo. Este repo es ese canal:

- **`version.txt`** — lo consume el juego (`PASTEBIN_URL` en `pu_config`). Contiene
  `GAME_VERSION`, `CHANGELOG` (multilínea) y `DOWNLOAD_URL` (descarga completa para primeras
  instalaciones).
- **`manifest.json`** — lista de archivos vigilados con su hash SHA-256. Lo usa el updater
  para bajar **solo lo que cambió** (deltas).
- **`files/`** — copia actual de cada archivo vigilado (Data/*.rxdata, Plugins/**, pu_config,
  serverinfo, mkxp.json). El updater descarga de aquí los que difieren.
- **`updater/`** — código del actualizador de deltas (`anil_updater.exe`, node+pkg). Se
  instala en `<juego>/poke_updater/anil_updater.exe`.
- **`tools/gen-manifest.js`** — generador del manifiesto y `version.txt`.

Descargas públicas por HTTPS: **no se usa ningún token ni credencial.**

Ver **RELEASING.md** para publicar una versión nueva.
