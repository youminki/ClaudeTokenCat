#!/bin/bash
# TokenCat.app 번들 + dmg 생성 (§6 M3).
#
# 사용법:
#   scripts/build-app.sh                          # 고정 identity 서명 (기본 "TokenCat Dev")
#   CODESIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
#   NOTARY_PROFILE=<notarytool keychain profile> CODESIGN_IDENTITY=... scripts/build-app.sh
#
# ⚠ ad-hoc 서명(-s -) 금지: 빌드마다 서명이 바뀌어 키체인 ACL·TCC 승인이 리셋됨.
#   identity가 없으면 scripts/setup-signing.sh 를 먼저 1회 실행.
# notarize까지 하려면 사전에 1회:
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-pw>
set -euo pipefail
cd "$(dirname "$0")/.."

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-TokenCat Dev}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$CODESIGN_IDENTITY"; then
  echo "✗ 코드서명 identity \"$CODESIGN_IDENTITY\" 없음 — 먼저 실행: scripts/setup-signing.sh" >&2
  exit 1
fi

# xcode-select가 CLT를 가리키는데 Xcode가 있으면 Xcode 툴체인 사용 (다른 머신 호환)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "▸ release 빌드"
swift build -c release

APP=dist/TokenCat.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/TokenCat "$APP/Contents/MacOS/"
# SPM 리소스 번들 (스프라이트 Assets) — Bundle.module이 Contents/Resources에서 찾음
if [ -d .build/release/TokenCat_TokenCat.bundle ]; then
  cp -R .build/release/TokenCat_TokenCat.bundle "$APP/Contents/Resources/"
fi
cp scripts/Info.plist "$APP/Contents/Info.plist"
# 설정 화면에서 지금 설치된 빌드가 어느 커밋인지 확인할 수 있게 남긴다 (+ = 커밋 안 된 변경 포함)
if COMMIT=$(git rev-parse --short HEAD 2>/dev/null); then
  [ -z "$(git status --porcelain 2>/dev/null)" ] || COMMIT="$COMMIT+"
  /usr/libexec/PlistBuddy -c "Add :TokenCatCommit string $COMMIT" "$APP/Contents/Info.plist"
fi
cp assets/AppIcon.icns "$APP/Contents/Resources/"

echo "▸ 서명: $CODESIGN_IDENTITY"
codesign --force --deep -s "$CODESIGN_IDENTITY" "$APP"

echo "▸ dmg 생성"
hdiutil create -volname TokenCat -srcfolder "$APP" -ov -format UDZO dist/TokenCat.dmg > /dev/null

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ notarize 제출"
  xcrun notarytool submit dist/TokenCat.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler staple dist/TokenCat.dmg
fi

echo "✓ 완료: $APP, dist/TokenCat.dmg"
codesign -dv "$APP" 2>&1 | grep -E "Identifier=|Authority" || true
