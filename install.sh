#!/bin/bash
# TokenCat 원클릭 설치: 서명 identity 준비 → 빌드 → 응용 프로그램 폴더로 복사 → 실행.
#
#   git clone https://github.com/youminki/ClaudeTokenCat.git && cd ClaudeTokenCat && ./install.sh
#
# 로컬에서 빌드하므로 Gatekeeper 격리(quarantine) 없이 바로 실행된다.
set -euo pipefail
cd "$(dirname "$0")"

echo "🐱 TokenCat 설치를 시작합니다"

# 1) Swift 툴체인 확인
if ! command -v swift > /dev/null; then
  echo "✗ Swift가 없습니다. Xcode 또는 Command Line Tools를 설치하세요:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

# 2) 고정 서명 identity (최초 1회 — macOS가 로그인 암호를 물으면 승인)
scripts/setup-signing.sh

# 3) 빌드
scripts/build-app.sh

# 4) 응용 프로그램 폴더로 설치 (/Applications 불가 시 ~/Applications)
TARGET="/Applications"
if [ ! -w "$TARGET" ]; then
  TARGET="$HOME/Applications"
  mkdir -p "$TARGET"
fi
pkill -x TokenCat 2>/dev/null || true
# 종료가 끝나기 전에 open하면 LaunchServices가 -600으로 실행을 거부한다
for _ in $(seq 1 50); do pgrep -x TokenCat > /dev/null || break; sleep 0.1; done
rm -rf "$TARGET/TokenCat.app"
cp -R dist/TokenCat.app "$TARGET/"

# 5) 실행
open "$TARGET/TokenCat.app"

cat <<'GUIDE'

✅ 설치 완료 — 메뉴바에 고양이가 나타납니다.

첫 실행 안내 (각 1회):
  • 키체인 프롬프트("security가 ... 접근하려고 합니다")가 뜨면
    반드시 [항상 허용]을 누르세요. [허용]만 누르면 다음에 또 묻습니다.
  • 알림 권한 요청은 한도 80%/95% 경고에 쓰입니다 — 허용 권장.

제거: 응용 프로그램 폴더에서 TokenCat.app 삭제.
업데이트: git pull && ./install.sh
GUIDE
