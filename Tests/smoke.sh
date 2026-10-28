#!/bin/zsh
# 冒烟测试：验证敲入引擎能通过 CGEvent 把中英文 / Shift 符号 / 换行完整敲进另一个应用。
#
# 需要：./build.sh dev 构建过；运行脚本的终端已在「辅助功能」里获得权限。
# 注意：会短暂打开一个测试窗口并覆盖当前剪贴板，请不要在测试期间切换窗口。
# 脚本退出时会尝试把剪贴板恢复成测试前的文本——但 pbpaste/pbcopy 只能往返纯文本，
# 图像、富文本、文件列表等剪贴板内容无法恢复，测试前请自行保存好。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MacExpert.app/Contents/MacOS/MacExpert"
[[ -x "$APP" ]] || { echo "先运行 ./build.sh dev"; exit 1; }

# 先备份剪贴板纯文本；trap EXIT 保证无论成功、失败还是 Ctrl-C 都会恢复。
CLIP_BACKUP="$(mktemp "${TMPDIR:-/tmp}/macexpert-clipboard.XXXXXX")"
HAD_CLIP_TEXT=0
if pbpaste > "$CLIP_BACKUP" 2>/dev/null && [[ -s "$CLIP_BACKUP" ]]; then
  HAD_CLIP_TEXT=1
fi
restore_clipboard() {
  if (( HAD_CLIP_TEXT )); then
    pbcopy < "$CLIP_BACKUP" || true
  fi
  rm -f "$CLIP_BACKUP"
}
trap restore_clipboard EXIT
if (( HAD_CLIP_TEXT )); then
  echo "== 已备份当前剪贴板文本，测试结束后恢复 =="
else
  echo "== 当前剪贴板没有纯文本可备份（图像/富文本无法恢复，测试结束不会覆盖回去） =="
fi

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
swiftc -O -sdk "$SDK" -target arm64-apple-macosx15.0 Tests/TypeTarget.swift -o build/tests/TypeTarget

SAMPLE=$'Hello, World! 123 #@$%&*()_+-=[]{}:;",./<>?\n中文测试：你好，世界。\n第三行 end'

# 接收窗口要开多久：按 dev 构建的实际 paceMs（UserDefaults 缺省 100）估算
# 敲入时长 = 字符数 × pace / 1000 + 10 秒收尾余量，至少 18 秒。
PACE_MS=$(defaults read com.slh.macexpert.dev paceMs 2>/dev/null || echo 100)
[[ -n "$PACE_MS" ]] || PACE_MS=100
CHARS=${#SAMPLE}
DURATION=$(awk -v chars="$CHARS" -v pace="$PACE_MS" \
  'BEGIN { d = chars * pace / 1000 + 10; if (d < 18) d = 18; printf "%d", d }')
echo "== 接收窗口 ${DURATION}s（${CHARS} 字符 × ${PACE_MS}ms + 10s，最少 18s） =="

printf '%s' "$SAMPLE" | pbcopy
printf '%s' "$SAMPLE" > build/tests/expected.txt
rm -f build/tests/actual.txt

echo "== 打开接收窗口（不要切换窗口） =="
./build/tests/TypeTarget build/tests/actual.txt "$DURATION" > build/tests/target.log 2>&1 &
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
