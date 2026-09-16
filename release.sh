#!/usr/bin/env bash
#===============================================================================
# Añil - Release en un comando (post-recompilado)
#===============================================================================
# Hace, en orden:
#   1) sube CURRENT_GAME_VERSION en pu_config
#   2) node tools/gen-manifest.js (manifest + manifest-lite + version.txt)
#   3) git commit + push  -> los jugadores de PC lo reciben in-game (deltas)
#   4) arma el ZIP limpio del juego
#   5) sube el ZIP a Google Drive ACTUALIZANDO el mismo archivo (mismo link)
#
# ANTES de correr esto: haz tus cambios en el juego, RECOMPILA los plugins
# (baile del $DEBUG) y deja Scripts.rxdata LIMPIO. Este script NO recompila
# (eso requiere abrir el juego).
#
# Uso:
#   ./release.sh 4.2.0 changelog.txt "Notas del commit (opcional)"
#===============================================================================
set -uo pipefail

# ============================ CONFIG (edita una vez) ==========================
GAME_DIR="E:/Pokemon Super añil randomlocke/Pokemon Anil V4.13"
UPDATER_DIR="E:/Pokemon Super añil randomlocke/anil-game-updater"
SEVENZIP="/c/Program Files/7-Zip/7z.exe"
RCLONE="rclone"                       # o la ruta completa a rclone.exe
# Destino en Drive: "<remoto>:<nombre EXACTO del archivo actual en tu Drive>".
# Debe coincidir con el archivo que ya tienes subido (mismo nombre = mismo ID = mismo link).
# Si esta en una carpeta: "gdrive:Carpeta/Pokemon_Anil.zip".
DRIVE_DEST="gdrive:Pokemon_Anil_4.0_Online_Edition.zip"
ZIP_OUT="E:/Pokemon Super añil randomlocke/Pokemon_Anil_release.zip"
CLEAN_SCRIPTS_SIZE=1259143            # tamaño de Scripts.rxdata LIMPIO (sin \$DEBUG)
# =============================================================================

VERSION="${1:-}"
CHANGELOG="${2:-}"
COMMITMSG="${3:-v$VERSION}"
if [[ -z "$VERSION" || -z "$CHANGELOG" ]]; then
  echo "Uso: ./release.sh <version> <changelog.txt> [\"mensaje commit\"]"; exit 1
fi
[[ -f "$CHANGELOG" ]] || { echo "No existe el changelog: $CHANGELOG"; exit 1; }

# --- Seguridad: no publicar un build en modo DEBUG ---
sz=$(stat -c %s "$GAME_DIR/Data/Scripts.rxdata" 2>/dev/null || echo 0)
if [[ "$sz" != "$CLEAN_SCRIPTS_SIZE" ]]; then
  echo "ABORTA: Scripts.rxdata mide $sz (esperado $CLEAN_SCRIPTS_SIZE = limpio)."
  echo "Restaura el Scripts.rxdata limpio antes de publicar (no dejes el de \$DEBUG)."
  exit 1
fi

echo ">> 1/5  pu_config -> $VERSION"
sed -i -E "s/^CURRENT_GAME_VERSION=.*/CURRENT_GAME_VERSION=$VERSION/" "$GAME_DIR/pu_config"

echo ">> 2/5  gen-manifest"
( cd "$UPDATER_DIR" && node tools/gen-manifest.js --version "$VERSION" --changelog "$CHANGELOG" ) || { echo "fallo gen-manifest"; exit 1; }

echo ">> 3/5  git commit + push"
( cd "$UPDATER_DIR" && git add -A && (git commit -m "$COMMITMSG" || echo "  (nada nuevo que commitear)") && git push origin main ) || { echo "fallo git push"; exit 1; }

echo ">> 4/5  ZIP limpio del juego"
rm -f "$ZIP_OUT"
parent="$(dirname "$GAME_DIR")"; base="$(basename "$GAME_DIR")"
( cd "$parent" && "$SEVENZIP" a -tzip -mx=3 "$ZIP_OUT" "$base" \
    -xr!Fotos "-xr!cable_club_pokemon_processor.py" \
    "-xr!Scripts.rxdata.DEBUG_injected_bak" "-xr!Scripts.rxdata.prebak*" "-xr!Scripts.rxdata.anil_clean_hold" \
    -xr!.DS_Store -xr!Thumbs.db "-xr!*.tmp" "-xr!*.log" "-xr!*.anilnew" "-xr!errorlog.txt" "-xr!anil_*.txt" >/dev/null ) \
  || { echo "fallo 7-Zip"; exit 1; }
echo "   ZIP: $ZIP_OUT ($(stat -c %s "$ZIP_OUT" | awk '{printf "%.0f MB", $1/1048576}'))"

echo ">> 5/5  subir a Drive (mismo link)"
"$RCLONE" copyto "$ZIP_OUT" "$DRIVE_DEST" --progress || { echo "fallo rclone"; exit 1; }

echo ""
echo "LISTO. Canal $VERSION publicado (PC recibe deltas in-game) y ZIP actualizado en Drive (mismo link para movil)."
