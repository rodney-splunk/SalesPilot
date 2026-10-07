#!/bin/bash
# Package SalesPilot as a signed .app bundle in ~/Applications.
set -euo pipefail
export PATH=/opt/homebrew/bin:$PATH
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Pick an SDK by TESTING one, not by comparing version numbers. Command Line Tools ships SDKs whose
# SwiftUI declares @State as a macro without shipping the plugin that implements it, so those SDKs
# cannot compile this app at all. A version heuristic ("newest SDK not newer than the OS") worked
# until macOS itself moved to 27, at which point it happily selected the broken one again. Compiling
# a three-line SwiftUI probe answers the question directly and cannot rot.
if [ -z "${SDKROOT:-}" ]; then
  PROBE=$(mktemp -t sdkprobe).swift
  printf 'import SwiftUI\nstruct P: View { @State private var n = 0; var body: some View { Text("\\(n)") } }\n' > "$PROBE"
  for cand in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -Vr); do
    if swiftc -c "$PROBE" -target arm64-apple-macos13 -sdk "$cand" -o /dev/null >/dev/null 2>&1; then
      export SDKROOT="$cand"; break
    fi
  done
  rm -f "$PROBE" 2>/dev/null
  [ -z "${SDKROOT:-}" ] && echo "==> WARNING: no SDK here can compile SwiftUI; build will fail" >&2
fi
echo "==> Building release binary… (SDK: $(basename "${SDKROOT:-default}"))"
swift build -c release --disable-sandbox

APP="${SALESPILOT_APP_PATH:-$HOME/Applications/SalesPilot.app}"
# Preserve the already-authorized reader across development builds. Self-signed
# login-keychain partitions can be build-hash-specific despite a stable DR.
HELPER_SOURCE="${SALESPILOT_CREDENTIAL_HELPER_SOURCE:-$HOME/Applications/SalesPilot.app}"
if [ -d "$HELPER_SOURCE/Contents/Helpers/CredentialAccess.app" ]; then
  HELPER_SOURCE="$HELPER_SOURCE/Contents/Helpers/CredentialAccess.app"
fi
HELPER_STAGE=""
if [ -d "$HELPER_SOURCE" ]; then
  codesign --verify --deep --strict "$HELPER_SOURCE"
  HELPER_STAGE=$(mktemp -d /private/tmp/salespilot-credential-reader.XXXXXX)
  cp -R "$HELPER_SOURCE" "$HELPER_STAGE/CredentialAccess.app"
fi
trap '[ -z "$HELPER_STAGE" ] || rm -rf "$HELPER_STAGE"' EXIT
# Refuse to replace a trusted installed identity with an ad-hoc update.
SIGN_ID="SalesPilot Self-Signed"
security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID" || SIGN_ID="-"
if [ -d "$APP" ] && [ "$SIGN_ID" = "-" ] && codesign -dv "$APP" 2>&1 | grep -q 'Authority='; then
  echo "Signing identity unavailable: keep the installed app intact. Restore its signing identity or build to a separate SALESPILOT_APP_PATH." >&2
  exit 1
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ -n "$HELPER_STAGE" ]; then
  mkdir -p "$APP/Contents/Helpers"
  cp -R "$HELPER_STAGE/CredentialAccess.app" "$APP/Contents/Helpers/"
fi
cp .build/release/open-wispr "$APP/Contents/MacOS/SalesPilot"
chmod +x "$APP/Contents/MacOS/SalesPilot"

# --- app icon (best-effort; uses the persistent Pillow venv if present) ---
ICON_LINE=""
PYICON="$HOME/Documents/sales-copilot/.iconvenv/bin/python"
[ -x "$PYICON" ] || PYICON=python3
if "$PYICON" - "$APP/Contents/Resources" <<'PY' 2>/dev/null
import sys, os, subprocess, tempfile
try:
    from PIL import Image, ImageDraw
except Exception:
    sys.exit(1)
res = sys.argv[1]
tmp = tempfile.mkdtemp(); iconset = os.path.join(tmp, "AppIcon.iconset"); os.makedirs(iconset)
def draw(sz):
    img = Image.new("RGBA", (sz, sz), (0,0,0,0)); d = ImageDraw.Draw(img)
    pad = int(sz*0.08); r = int(sz*0.22)
    d.rounded_rectangle([pad,pad,sz-pad,sz-pad], radius=r, fill=(10,108,255,255))
    bars=[0.35,0.62,0.9,0.62,0.35]; bw=sz*0.07; gap=sz*0.05
    total=len(bars)*bw+(len(bars)-1)*gap; x=(sz-total)/2
    for h in bars:
        bh=sz*0.5*h; d.rounded_rectangle([x, sz/2-bh/2, x+bw, sz/2+bh/2], radius=bw/2, fill=(255,255,255,255)); x+=bw+gap
    return img
for px,name in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")]:
    draw(px).save(os.path.join(iconset, f"icon_{name}.png"))
subprocess.run(["iconutil","-c","icns","-o",os.path.join(res,"AppIcon.icns"),iconset], check=True)
print("ok")
PY
then
  ICON_LINE="  <key>CFBundleIconFile</key><string>AppIcon</string>"
  echo "==> icon generated"
else
  echo "==> (no Pillow — using generic icon)"
fi

WORKSPACE_ROOT="${SALESPILOT_WORKSPACE_ROOT:-$(dirname "$DIR")}"
WORKSPACE_XML=$(python3 -c 'import html,sys; print(html.escape(sys.argv[1]))' "$WORKSPACE_ROOT")
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SalesPilotWorkspaceRoot</key><string>$WORKSPACE_XML</string>
  <key>CFBundleName</key><string>SalesPilot</string>
  <key>CFBundleDisplayName</key><string>SalesPilot</string>
  <key>CFBundleIdentifier</key><string>com.salespilot.app</string>
  <key>CFBundleExecutable</key><string>SalesPilot</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSMicrophoneUsageDescription</key><string>SalesPilot transcribes your side of the call on-device.</string>
  <key>NSAppleEventsUsageDescription</key><string>SalesPilot reads your next meeting from Outlook and can open Terminal for logins.</string>
  <key>NSAudioCaptureUsageDescription</key><string>SalesPilot captures the customer's audio from your call app to transcribe it.</string>
$ICON_LINE
</dict>
</plist>
PLIST

# Record only tracked source hashes, never local configuration, customer data or credentials.
python3 - "$WORKSPACE_ROOT" "$DIR/.." "$APP/Contents/Resources/build-manifest.json" <<'PY'
import hashlib, json, pathlib, subprocess, sys
runtime, source, output = map(pathlib.Path, sys.argv[1:])
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
tracked = subprocess.check_output(['git', 'ls-files', '-z', 'engine', 'open-wispr/Sources'], cwd=source).decode().split('\0')
files = {name: hashlib.sha256((source/name).read_bytes()).hexdigest() for name in tracked
         if name and (source/name).is_file() and pathlib.Path(name).suffix in {'.swift', '.mjs', '.py'}}
dirty = bool(subprocess.check_output(['git', 'status', '--porcelain', '--', 'engine', 'open-wispr/Sources'], cwd=source))
output.write_text(json.dumps({'schemaVersion': 1, 'sourceRevision': revision, 'sourceModified': dirty,
                             'sourceFiles': files}, indent=2) + '\n')
PY

# Sign with the stable self-signed identity if present (so TCC permission grants survive rebuilds);
# fall back to ad-hoc only if the cert isn't installed.
echo "==> Code signing with: $SIGN_ID"
# Do not re-sign the preserved credential reader: its authorized code hash is stable.
codesign --force --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -iE "Authority|Identifier" | head -2 || true
echo "==> Built: $APP"
