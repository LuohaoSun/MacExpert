#!/bin/zsh
# 构建并签名 MacExpert.app（只需 Xcode Command Line Tools）
#
#   ./build.sh           开发构建：带 dev 钩子（--preview / --notify-drive / --drive-once / --selfcheck）
#   ./build.sh release   发布构建：编掉全部 dev 钩子，可以分发
#
# 固定 -target arm64-apple-macosx13.0：
# 不指定 target 时 swiftc 会拿编译机的系统版本当最低版本（本机 macOS 27 → minos 27.0），
# 那样的包别人打不开，而且 Info.plist 里的 LSMinimumSystemVersion 拦不住它——
# Mach-O 的 load command 才是被强制的那个。
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-dev}"
if [[ "$MODE" != "dev" && "$MODE" != "release" ]]; then
  echo "用法: ./build.sh [dev|release]" >&2
  exit 2
fi

DEPLOY_TARGET="arm64-apple-macosx13.0"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SOURCES=(${(f)"$(find Sources -name '*.swift' -print | sort)"})
FLAGS=(-O -swift-version 5 -target "$DEPLOY_TARGET" -sdk "$SDK" -module-name MacExpert)

if [[ "$MODE" == "dev" ]]; then
  FLAGS+=(-D MACEXPERT_DEV_HOOKS)
  OUT=build
else
  OUT=build/release
fi

mkdir -p "$OUT"
echo "== swiftc ($MODE, $DEPLOY_TARGET) =="
swiftc "${FLAGS[@]}" "${SOURCES[@]}" -o "$OUT/MacExpert"

APP="$OUT/MacExpert.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/MacExpert" "$APP/Contents/MacOS/MacExpert"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "== codesign =="
codesign --force --sign - "$APP"

echo "== 校验 =="
lipo -info "$OUT/MacExpert" | sed 's/^/  /'
vtool -show-build "$OUT/MacExpert" | grep -E "minos|platform" | sed 's/^/  /'
if [[ "$MODE" == "release" ]]; then
  # dev 钩子痕迹必须从二进制里彻底消失，否则编译期开关就没生效。
  LEAKED=0
  for pat in "com.slh.macexpert.drive" "--notify-drive" "--drive-once" \
             "--preview" "--selfcheck"; do
    if strings "$OUT/MacExpert" | grep -qF -e "$pat"; then
      echo "  ❌ 发布构建里仍存在测试钩子入口: $pat"
      LEAKED=1
    fi
  done
  if (( LEAKED )); then
    echo "    别分发这个包。"
    exit 1
  fi
  echo "  ✓ 二进制中已无测试钩子入口（通知名与命令行开关均已编掉）"
fi

echo "== done =="
echo "$PWD/$APP"
if [[ "$MODE" == "dev" ]]; then
  echo "⚠️  开发构建：含 dev 钩子，任何本机进程都能经分布式通知驱动它敲键盘。"
  echo "    要发给别人请用 ./build.sh release"
else
  echo "✅ 发布构建：dev 钩子已编掉，可分发。"
fi
