#!/bin/zsh
set -euo pipefail

REPO_DIR="/Users/joru2/Applications/MLXAudio"
DEPLOY_ROOT="$HOME/Applications/LocalVoiceUtility"
APP_DIR="/Users/joru2/Applications/LocalVoiceUtility.app"
SIGN_IDENTITY="${LOCALVOICE_SIGN_IDENTITY:--}"

cd "$REPO_DIR"
swift build -c release --product LocalVoiceUtility
swift build -c release --product local-voice-utility-cli

mkdir -p "$DEPLOY_ROOT/bin"
cp -f .build/release/LocalVoiceUtility "$DEPLOY_ROOT/bin/LocalVoiceUtility"
cp -f .build/release/local-voice-utility-cli "$DEPLOY_ROOT/bin/local-voice-utility-cli"

# Keep the same app bundle path/identity between installs to preserve TCC permissions.
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp -f "$DEPLOY_ROOT/bin/LocalVoiceUtility" "$APP_DIR/Contents/MacOS/LocalVoiceUtility"
chmod +x "$APP_DIR/Contents/MacOS/LocalVoiceUtility"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>LocalVoiceUtility</string>
  <key>CFBundleIdentifier</key>
  <string>com.localvoiceutility.desktop</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LocalVoiceUtility</string>
  <key>CFBundleDisplayName</key>
  <string>Local Voice Utility</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <false/>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Local Voice Utility uses microphone input for realtime speech transcription.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Local Voice Utility uses speech recognition to provide live transcription.</string>
</dict>
</plist>
PLIST

touch "$APP_DIR"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

# Sign deterministically so macOS sees a stable app identity across updates.
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null 2>&1 || true

echo "Installed app bundle at: $APP_DIR"
echo "CLI binary at: $DEPLOY_ROOT/bin/local-voice-utility-cli"
echo "Code signing identity: $SIGN_IDENTITY"
