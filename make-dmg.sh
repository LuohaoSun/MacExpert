#!/bin/zsh
# 打一个带拖拽引导的 DMG：MacExpert.app 与「应用程序」快捷方式并排放好。
#
#   ./make-dmg.sh
#
# 产物: build/release/MacExpert-<版本>.dmg
# 依赖: 只用系统自带的 hdiutil / ditto / swiftc。
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
STAGE="build/dmg-stage"
OUT="build/release/MacExpert-$VERSION.dmg"

echo "== 1/3 发布构建 =="
./build.sh release

echo "== 2/3 准备 DMG 内容 =="
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto build/release/MacExpert.app "$STAGE/MacExpert.app"
ln -s /Applications "$STAGE/Applications"

echo "== 3/3 生成 DMG =="
rm -f "$OUT"
hdiutil create -volname "MacExpert" -srcfolder "$STAGE" -fs HFS+ -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"

echo "== done =="
echo "$PWD/$OUT"
shasum -a 256 "$OUT"
