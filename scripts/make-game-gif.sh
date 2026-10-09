#!/bin/zsh
# README 게임 GIF 만들기: 앱으로 장면을 찍고 ffmpeg로 256색 GIF를 만든다. ffmpeg가 있어야 한다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMES="$(mktemp -d)"
trap 'rm -rf "$FRAMES"' EXIT
cd "$ROOT"
swift build
.build/debug/RunTime --game-frames "$FRAMES"
ffmpeg -v error -y -framerate 20 -i "$FRAMES/%04d.png" \
    -vf "scale=516:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    assets/runtime-game.gif
ls -la assets/runtime-game.gif
