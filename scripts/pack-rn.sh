#!/usr/bin/env bash
# Pack @omnix/voice-sdk npm tarball (SDK-046). Linux/macOS CI twin of pack-rn.ps1.
set -euo pipefail

fail() { echo "pack-rn: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
RN="$ROOT/react-native"
DIST="$ROOT/dist"
MAVEN="$RN/android/maven/com/omnix/voice/omnix-voice-sdk/$VERSION"
AAR_NAME="OmnixVoiceSDK-${VERSION}.aar"

[[ -f "$RN/package.json" ]] || fail "missing react-native/package.json"
mkdir -p "$DIST" "$MAVEN"

AAR=""
for c in \
  "$ROOT/android/build/outputs/aar/$AAR_NAME" \
  "$ROOT/android/build/outputs/aar/OmnixVoiceSDK-release.aar" \
  "$DIST/$AAR_NAME"
do
  if [[ -f "$c" ]]; then AAR="$c"; break; fi
done

if [[ -z "$AAR" ]]; then
  echo "pack-rn: building android assembleRelease"
  (
    cd "$ROOT/android"
    ./gradlew assembleRelease --no-daemon
  )
  AAR="$ROOT/android/build/outputs/aar/$AAR_NAME"
  if [[ ! -f "$AAR" ]]; then
    AAR="$(ls "$ROOT/android/build/outputs/aar"/OmnixVoiceSDK-*.aar 2>/dev/null | head -n 1 || true)"
  fi
fi
[[ -f "${AAR:-}" ]] || fail "OmnixVoiceSDK AAR not found"

cp -f "$AAR" "$MAVEN/omnix-voice-sdk-${VERSION}.aar"

cat > "$MAVEN/omnix-voice-sdk-${VERSION}.pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.omnix.voice</groupId>
  <artifactId>omnix-voice-sdk</artifactId>
  <version>${VERSION}</version>
  <packaging>aar</packaging>
</project>
EOF

cat > "$RN/android/maven/com/omnix/voice/omnix-voice-sdk/maven-metadata.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>com.omnix.voice</groupId>
  <artifactId>omnix-voice-sdk</artifactId>
  <versioning>
    <release>${VERSION}</release>
    <versions><version>${VERSION}</version></versions>
  </versioning>
</metadata>
EOF

if [[ -d "$ROOT/dist/OmnixVoiceSDK.xcframework" ]]; then
  rm -rf "$RN/ios/OmnixVoiceSDK.xcframework"
  cp -R "$ROOT/dist/OmnixVoiceSDK.xcframework" "$RN/ios/OmnixVoiceSDK.xcframework"
  echo "pack-rn: copied OmnixVoiceSDK.xcframework"
else
  echo "pack-rn: WARN — OmnixVoiceSDK.xcframework absent (SDK-043)"
fi

cp -f "$ROOT/THIRD_PARTY_NOTICES.md" "$RN/THIRD_PARTY_NOTICES.md"

# Nested maven/.gitignore ignores *.aar — rename for npm pack.
MAVEN_GI="$RN/android/maven/.gitignore"
MAVEN_GI_BAK="${MAVEN_GI}.packbak"
if [[ -f "$MAVEN_GI" ]]; then
  mv "$MAVEN_GI" "$MAVEN_GI_BAK"
fi

(
  cd "$RN"
  if [[ ! -f package-lock.json ]]; then
    npm install --ignore-scripts --no-fund --no-audit --legacy-peer-deps
  fi
  npm pack --pack-destination "$DIST"
)
PACK_RC=$?
if [[ -f "$MAVEN_GI_BAK" ]]; then
  mv "$MAVEN_GI_BAK" "$MAVEN_GI"
fi
[[ $PACK_RC -eq 0 ]] || fail "npm pack failed"

TGZ="$DIST/omnix-voice-sdk-${VERSION}.tgz"
if [[ ! -f "$TGZ" ]]; then
  FOUND="$(ls "$DIST"/*omnix-voice-sdk*"${VERSION}"*.tgz 2>/dev/null | head -n 1 || true)"
  [[ -n "$FOUND" ]] || fail "tarball not produced"
  cp -f "$FOUND" "$TGZ"
fi
echo "pack-rn: SUCCESS -> $TGZ"
shasum -a 256 "$TGZ" || true
