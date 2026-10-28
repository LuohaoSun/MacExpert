#!/bin/zsh
# 冒烟测试：验证敲入引擎能通过 CGEvent 把中英文 / Shift 符号 / 换行完整敲进另一个应用。
#
# 需要：./build.sh dev 构建过；运行脚本的终端已在「辅助功能」里获得权限。
# 注意：会短暂打开一个测试窗口并覆盖当前剪贴板，请不要在测试期间切换窗口。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacExpert.app/Contents/MacOS/MacExpert"
[[ -x "$APP" ]] || { echo "先运行 ./build.sh dev"; exit 1; }

TRUST_OUTPUT="$("$APP" --selfcheck)"
TRUST="${TRUST_OUTPUT%%$'\n'*}"
if [[ "$TRUST" != "trusted:true" ]]; then
  echo "❌ 当前终端没有辅助功能权限（$TRUST）"
  echo "   系统设置 → 隐私与安全性 → 辅助功能 → 勾选终端"
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p build/tests
echo "== 编译接收端 =="
swiftc -O -sdk "$SDK" -target arm64-apple-macosx13.0 Tests/TypeTarget.swift -o build/tests/TypeTarget

SAMPLE=$'Hello, World! 123 #@$%&*()_+-=[]{}:;",./<>?\n中文测试：你好，世界。\n第三行 end'
printf '%s' "$SAMPLE" | pbcopy
printf '%s' "$SAMPLE" > build/tests/expected.txt
rm -f build/tests/actual.txt

echo "== 打开接收窗口（不要切换窗口） =="
./build/tests/TypeTarget build/tests/actual.txt 18 > build/tests/target.log 2>&1 &
TARGET_PID=$!
sleep 2

echo "== 开始敲入 =="
"$APP" --drive-once | tail -2

wait $TARGET_PID || true

if [[ ! -f build/tests/actual.txt ]]; then
  echo "❌ 接收端没有写出结果"
  cat build/tests/target.log
  exit 1
fi

if cmp -s build/tests/actual.txt build/tests/expected.txt; then
  echo "✅ 冒烟测试通过（中英文、Shift 符号、换行全部一致）"
else
  echo "❌ 文本不一致"
  diff -u build/tests/expected.txt build/tests/actual.txt || true
  exit 1
fi
