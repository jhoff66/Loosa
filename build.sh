#!/bin/zsh
# Compila o Loosa e monta o Loosa.app nesta pasta.
# `./build.sh install` também copia para /Applications e reabre.
# `./build.sh dmg` também gera o Loosa.dmg.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 Sources/Loosa/*.swift -o build/Loosa-$arch
done
lipo -create build/Loosa-arm64 build/Loosa-x86_64 -output build/Loosa

APP="Loosa.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Loosa "$APP/Contents/MacOS/Loosa"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Loosa</string>
  <key>CFBundleDisplayName</key><string>Loosa</string>
  <key>CFBundleIdentifier</key><string>br.com.jhosefer.loosa</string>
  <key>CFBundleExecutable</key><string>Loosa</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# Assinatura: com um certificado Apple Development, o macOS lembra a permissão de
# Gravação de Tela entre recompilações. Sem ele (ou no DMG, que vai para outras
# máquinas), usa assinatura ad hoc.
ID=""
if [[ "${1:-}" != "dmg" ]]; then
  ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
fi
codesign --force --sign "${ID:--}" "$APP"
echo "Assinado com: ${ID:-ad hoc}"
echo "Pronto: $PWD/$APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Loosa || true
  rm -rf /Applications/Loosa.app
  cp -R "$APP" /Applications/Loosa.app
  open /Applications/Loosa.app
  echo "Instalado em /Applications/Loosa.app"
fi

if [[ "${1:-}" == "dmg" ]]; then
  STAGE="build/dmg"
  rm -rf "$STAGE" Loosa.dmg
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cat > "$STAGE/Se não abrir, leia.txt" <<'TXT'
O Loosa não é notarizado pela Apple, então o macOS pode barrar a primeira abertura,
às vezes dizendo que o app "está danificado". O app não está danificado.

Depois de arrastar o Loosa para Applications, abra o Terminal e cole:

    xattr -cr /Applications/Loosa.app

Depois abra o app normalmente.

Alternativa sem este DMG, que já instala e libera de uma vez:

    curl -fsSL https://raw.githubusercontent.com/jhoff66/Loosa/main/install.sh | bash
TXT
  hdiutil create -volname "Loosa" -srcfolder "$STAGE" -ov -format UDZO Loosa.dmg >/dev/null
  rm -rf "$STAGE"
  echo "DMG: $PWD/Loosa.dmg"
fi
