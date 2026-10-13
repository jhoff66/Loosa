#!/bin/bash
# Instala a versão mais recente do Loosa em /Applications.
# Baixar pelo terminal evita o bloqueio que o macOS aplica a apps não notarizados vindos do navegador.
set -euo pipefail

URL="https://github.com/jhoff66/Loosa/releases/latest/download/Loosa.dmg"
TMP="$(mktemp -d)"
MOUNT="$TMP/mount"
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "Baixando o Loosa..."
curl -fsSL "$URL" -o "$TMP/Loosa.dmg"
mkdir -p "$MOUNT"
hdiutil attach "$TMP/Loosa.dmg" -nobrowse -quiet -mountpoint "$MOUNT"

pkill -x Loosa 2>/dev/null || true
rm -rf /Applications/Loosa.app
cp -R "$MOUNT/Loosa.app" /Applications/
xattr -cr /Applications/Loosa.app

open /Applications/Loosa.app
echo "Pronto: o Loosa está na barra de menus."
