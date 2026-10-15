#!/bin/bash
# Installs (or removes) the DOOM (2016) patched MoltenVK into NotProton's CrossOver runner(s).
#
#   Install:    curl -fsSL https://raw.githubusercontent.com/quanticdynamics/MoltenVK-DOOM2016/main/install-doom2016.sh | bash
#   Uninstall:  curl -fsSL https://raw.githubusercontent.com/quanticdynamics/MoltenVK-DOOM2016/main/install-doom2016.sh | bash -s -- --uninstall
#
# Only files inside ~/Library/Application Support/notproton/runners are touched.
# Every original file is kept next to it as <name>.bak and restored by --uninstall.

set -euo pipefail

REPO="quanticdynamics/MoltenVK-DOOM2016"
DOWNLOAD="https://github.com/${REPO}/releases/latest/download"
RUNNERS="${HOME}/Library/Application Support/notproton/runners"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

MODE="install"
case "${1:-}" in
  ""|--install) MODE="install" ;;
  --uninstall)  MODE="uninstall" ;;
  *) die "Unknown option '$1'. Use --uninstall to remove the patch." ;;
esac

[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS."
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] || die "This patch is for Apple Silicon Macs (M1 or newer)."

if pgrep -xq steam_osx; then
  die "Steam is running. Quit Steam completely (Steam menu → Quit Steam), then run this again."
fi

[ -d "$RUNNERS" ] || die "NotProton's CrossOver runner wasn't found at:
  $RUNNERS
Install and set up NotProton first, and launch DOOM once with it."

# Every real libMoltenVK dylib inside every NotProton runner (symlinks are skipped).
TARGETS=()
while IFS= read -r -d '' f; do TARGETS+=("$f"); done < <(find "$RUNNERS" -type f -name 'libMoltenVK*.dylib' -print0)

if [ "$MODE" = "uninstall" ]; then
  say "Restoring the original MoltenVK"
  found=0
  while IFS= read -r -d '' bak; do
    orig="${bak%.bak}"
    mv -f "$bak" "$orig"
    ok "restored ${orig#"$RUNNERS"/}"
    found=1
  done < <(find "$RUNNERS" -type f -name 'libMoltenVK*.dylib.bak' -print0)
  [ "$found" = 1 ] || say "Nothing to restore (no backups found)."
  say "Done. DOOM will use CrossOver's original MoltenVK again."
  exit 0
fi

[ "${#TARGETS[@]}" -gt 0 ] || die "No libMoltenVK.dylib found inside $RUNNERS"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading the patched MoltenVK"
curl -fL --progress-bar -o "$TMP/libMoltenVK.dylib"        "$DOWNLOAD/libMoltenVK.dylib" \
  || die "Download failed. Check your internet connection, or see https://github.com/${REPO}/releases"
curl -fsSL            -o "$TMP/libMoltenVK.dylib.sha256" "$DOWNLOAD/libMoltenVK.dylib.sha256" \
  || die "Couldn't download the checksum file."

( cd "$TMP" && shasum -a 256 -c libMoltenVK.dylib.sha256 >/dev/null ) \
  || die "Checksum mismatch: the download is corrupted. Nothing was changed."
ok "download verified"
# Architecture check: `lipo -archs` where available, else `file` (some setups have a non-Apple lipo first in PATH).
ARCHS="$( { /usr/bin/lipo -archs "$TMP/libMoltenVK.dylib" || lipo -archs "$TMP/libMoltenVK.dylib" || file -b "$TMP/libMoltenVK.dylib"; } 2>/dev/null || true)"
case "$ARCHS" in
  *x86_64*arm64*|*arm64*x86_64*) ;;
  *) die "Downloaded file isn't a universal (x86_64 + arm64) library (found: ${ARCHS:-unknown}). Nothing was changed." ;;
esac
xattr -d com.apple.quarantine "$TMP/libMoltenVK.dylib" 2>/dev/null || true

say "Installing into NotProton's CrossOver runner"
for f in "${TARGETS[@]}"; do
  [ -e "$f.bak" ] || cp -p "$f" "$f.bak"
  cp "$TMP/libMoltenVK.dylib" "$f"
  codesign --force --sign - "$f" >/dev/null 2>&1 || die "Couldn't sign $f"
  ok "patched ${f#"$RUNNERS"/}"
done

cat <<'EOF'

Done! Now, in Steam:
  1. Right-click DOOM → Properties → General → Launch Options, and paste:
       %command% +r_renderAPI 1 +com_skipIntroVideo 1
  2. Press Play. The first launch can show a black screen for a few minutes
     while shaders are prepared — that's normal.

If a NotProton or CrossOver update makes DOOM crash again, just run this installer again.
To undo:  curl -fsSL https://raw.githubusercontent.com/quanticdynamics/MoltenVK-DOOM2016/main/install-doom2016.sh | bash -s -- --uninstall
EOF
