#!/bin/bash
# Build, sign and send Anchor to TestFlight on team PY94U6N48R.
#   scripts/testflight.sh            archive + export + validate (nothing sent)
#   scripts/testflight.sh upload     the same, then upload
# Needs the team API key at ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 and xcodegen.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
: "${ASC_KEY_ID:=8C639TUNUX}"
: "${ASC_ISSUER_ID:=118eaf54-ab57-41fd-8ccc-737f501adab1}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$KEY" ] || { echo "Blocked: no API key at $KEY" >&2; exit 1; }
OUT=$(mktemp -d "${TMPDIR:-/tmp}/anchor-tf.XXXXXX")
BUILD=$(date -u +%y%m%d%H%M)
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
redact() { LC_ALL=C sed -E 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/<jwt>/g'; }

xcodegen generate --quiet
echo "Build $BUILD -> $OUT"
xcodebuild archive -scheme Anchor -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Anchor.xcarchive" -derivedDataPath "$OUT/dd" CURRENT_PROJECT_VERSION="$BUILD" "${AUTH[@]}" \
  2>&1 | redact | grep -E "error|\*\* ARCHIVE" || true
[ -d "$OUT/Anchor.xcarchive" ] || { echo "Blocked: archive failed" >&2; exit 1; }

cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>export</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>PY94U6N48R</string>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Anchor.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" "${AUTH[@]}" 2>&1 | redact | grep -E "error|\*\* EXPORT" || true
IPA="$OUT/export/Anchor.ipa"
[ -f "$IPA" ] || { echo "Blocked: export failed" >&2; exit 1; }
# Xcode writes bearer tokens into its export logs.
find "$OUT/export" -name '*.log' -exec sh -c 'LC_ALL=C sed -i "" -E "s/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/<jwt>/g" "$1"' _ {} \;

xcrun altool --validate-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | redact | tail -5
if [ "${1:-}" = "upload" ]; then
  xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | redact | tail -5
  echo "Uploaded build $BUILD"
fi
