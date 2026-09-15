# 🚀 Publicar una actualización del juego (deltas)

Con esto, cualquier cambio del juego (PluginScripts.rxdata, Scripts.rxdata, serverinfo, un
plugin `.rb`, etc.) llega a los jugadores **dentro del juego** y solo descargan lo cambiado.

> Requisitos: Node.js, `gh` (GitHub CLI con sesión), y este repo clonado en local.

## Pasos

1. **Haz y compila tus cambios en el juego** como siempre (recompila plugins con `$DEBUG`,
   restaura `Scripts.rxdata` limpio).

2. **Sube la versión** en el juego, archivo `pu_config` (raíz del juego):
   ```
   CURRENT_GAME_VERSION=4.1.3
   ```
   (Deja `PASTEBIN_URL` y `UPDATER_FILENAME` como están — apuntan a este canal.)

3. **Escribe el changelog** (una línea por novedad, sin `=` y sin líneas vacías):
   ```
   # changelog.txt
   - Lo que cambió 1
   - Lo que cambió 2
   ```

4. **Genera manifiesto + version.txt** (desde la raíz de este repo):
   ```bash
   node tools/gen-manifest.js --version 4.1.3 --changelog changelog.txt \
        --game "E:/Pokemon Super añil randomlocke/Pokemon Anil V4.13" \
        --download "https://<tu-enlace-de-Drive-al-build-completo>"
   ```
   Copia los archivos a `files/`, y crea `manifest.json` y `version.txt`.

5. **Sube el repo** (los jugadores lo leen al instante):
   ```bash
   git add -A && git commit -m "Juego v4.1.3: <resumen>" && git push
   ```

¡Listo! Al abrir el juego, quien tenga una versión anterior verá el aviso, las novedades y el
updater bajará solo los archivos cambiados y reabrirá el juego.

## Notas

- **Primera vez / bootstrap:** los jugadores con un build viejo (que apuntaba al canal del dev
  original) NO pueden auto-actualizarse a este sistema. Hay que repartir **una vez** por Drive
  un build completo que ya incluya el `pu_config` nuevo y `poke_updater/anil_updater.exe`. A
  partir de ahí, todo automático.
- `pu_config` está entre los archivos vigilados: al actualizar, el jugador recibe el nuevo
  `pu_config` (con `CURRENT_GAME_VERSION` ya subido), así el juego deja de avisar.
- El `anil_updater.exe` NO se vigila (no se auto-reemplaza mientras corre). Si lo cambias,
  repártelo con el próximo build completo por Drive.
- Cambiar la versión del juego usa versionado numérico (`4.1.3`); una versión "estable" es
  mayor que cualquier `-beta`/`-alpha`.
