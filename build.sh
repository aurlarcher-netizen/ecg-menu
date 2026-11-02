#!/bin/zsh
# Compile ECGMenu et assemble ECGMenu.app (app de barre des menus, sans icône dans le Dock)
set -e
cd "$(dirname "$0")"

swift build -c release
APP=ECGMenu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ECGMenu "$APP/Contents/MacOS/ECGMenu"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ECGMenu</string>
    <key>CFBundleIdentifier</key><string>local.ecgmenu</string>
    <key>CFBundleName</key><string>ECGMenu</string>
    <key>CFBundleDisplayName</key><string>ECG Menu</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "OK : $(pwd)/$APP"

# ./build.sh dmg → image disque à partager (app + raccourci vers Applications)
if [[ "$1" == "dmg" ]]; then
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cat > "$STAGE/Installation.txt" <<'TXT'
ECG Menu : compte rendu ECG rapide dans la barre des menus (macOS 14 ou plus récent)

1. Glisser « ECGMenu » dans le dossier Applications.
2. Premier lancement : clic droit sur l'app > Ouvrir, puis confirmer « Ouvrir ».
   (L'app n'est pas signée par un compte développeur Apple, macOS demande donc
   une confirmation la première fois. Si rien ne s'ouvre : Réglages Système >
   Confidentialité et sécurité > « Ouvrir quand même ».)
3. L'icône QRS apparaît dans la barre des menus : clic gauche pour le compte
   rendu, clic droit pour « Ouvrir au démarrage » ou « Quitter ».

Outil d'aide à la rédaction : le compte rendu reste à relire et valider.
TXT
    rm -f ECGMenu.dmg
    hdiutil create -volname "ECG Menu" -srcfolder "$STAGE" -ov -format UDZO ECGMenu.dmg >/dev/null
    rm -rf "$STAGE"
    echo "DMG : $(pwd)/ECGMenu.dmg"
fi
