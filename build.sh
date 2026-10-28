#!/bin/zsh
# 构建并签名 MacExpert.app（只需 Xcode Command Line Tools）
#
#   ./build.sh           开发构建：带 dev 钩子（--preview / --notify-drive / --drive-once / --selfcheck）
#   ./build.sh release   发布构建：编掉全部 dev 钩子，可以分发
#   ./build.sh test      只跑单元测试（Tests/run-tests.sh），不启动 App
#
# 固定 -target arm64-apple-macosx15.0：
# 不指定 target 时 swiftc 会拿编译机的系统版本当最低版本（本机 macOS 27 → minos 27.0），
# 那样的包别人打不开，而且 Info.plist 里的 LSMinimumSystemVersion 拦不住它——
# Mach-O 的 load command 才是被强制的那个。
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "test" ]]; then
  exec ./Tests/run-tests.sh
fi

MODE="${1:-dev}"
if [[ "$MODE" != "dev" && "$MODE" != "release" ]]; then
  echo "用法: ./build.sh [dev|release|test]" >&2
  exit 2
fi

DEPLOY_TARGET="arm64-apple-macosx15.0"
MIN_MACOS="15.0"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Support/Info.plist)
echo "== MacExpert $VERSION ($BUILD) · $MODE =="

if [[ "$MODE" == "release" ]]; then
  PLIST_MIN=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Support/Info.plist)
  if [[ "$PLIST_MIN" != "$MIN_MACOS" ]]; then
    echo "❌ Info.plist 的 LSMinimumSystemVersion 是 $PLIST_MIN，发布构建要求 $MIN_MACOS" >&2
    exit 1
  fi
  echo "   最低系统版本: $PLIST_MIN"
fi

SOURCES=(${(f)"$(find Sources -name '*.swift' -print | sort)"})
if [[ "$MODE" == "release" ]]; then
  # 双保险：PreviewRenderer 本身已有 #if MACEXPERT_DEV_HOOKS 包裹，
  # 这里再把整个 Sources/Dev 排除在编译单元之外，任何惰性字符串都进不了 release 二进制。
  SOURCES=(${SOURCES:#Sources/Dev/*})
fi

FLAGS=(-O -swift-version 5 -target "$DEPLOY_TARGET" -sdk "$SDK" -module-name MacExpert)
# 把 LC_BUILD_VERSION 的 platform/minos/sdk 三个字段都写准：
# 否则系统可能按旧版本的兼容外观渲染，SwiftUI 新控件和新窗口 chrome 都不会生效。
FLAGS+=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION")

if [[ "$MODE" == "dev" ]]; then
  FLAGS+=(-D MACEXPERT_DEV_HOOKS)
  OUT=build
else
  OUT=build/release
fi

mkdir -p "$OUT"
# build/ 里的 app 是开发产物，尽量别让 Spotlight 收录；
# 应用包本身还会在签名后从 LaunchServices 注销，避免启动台出现第二个 MacExpert。
touch build/.metadata_never_index "$OUT/.metadata_never_index"
echo "== swiftc ($MODE, $DEPLOY_TARGET) =="
swiftc "${FLAGS[@]}" "${SOURCES[@]}" -o "$OUT/MacExpert"

APP="$OUT/MacExpert.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/MacExpert" "$APP/Contents/MacOS/MacExpert"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [[ "$MODE" == "dev" ]]; then
  # 开发构建用独立 bundle id：否则和 /Applications 里的正式版同名，
  # LaunchServices 会互相抢启动，TCC 授权也会挂到错误的那一份上。
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.slh.macexpert.dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName MacExpert Dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName MacExpert Dev" "$APP/Contents/Info.plist"
fi
if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# 优先用本机自签证书：identity 稳定，重编后辅助功能授权不用反复点。
# 没有证书就退回 adhoc；adhoc 的 cdhash 每次重编都会变，系统会要求重新授权。
SIGN_IDENTITY="${MACEXPERT_SIGN_IDENTITY:-MacExpert Local Signing}"
# 先取成变量再匹配：set -o pipefail 下 security | grep -q 可能因 grep 提前退出
# 让 security 收到 SIGPIPE，导致“明明有证书却判定没有”。
# 这里故意不用 `find-identity -v`：自签证书如果没有在钥匙串里设“始终信任”，
# 会被 -v 过滤掉，但它仍然能正常签名（codesign --verify 也通过）。
# 未信任只影响 Gatekeeper 的 spctl 评估，本机自用不经过那一步。
SIGNING_IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
if grep -qF -- "\"$SIGN_IDENTITY\"" <<< "$SIGNING_IDENTITIES"; then
  echo "== codesign（自签: $SIGN_IDENTITY）=="
  if ! codesign --force --sign "$SIGN_IDENTITY" "$APP"; then
    echo "  ⚠️ 自签签名失败，退回 adhoc。"
    codesign --force --sign - "$APP"
  fi
else
  echo "== codesign（adhoc）=="
  codesign --force --sign - "$APP"
  echo "  ⚠️ 未找到代码签名证书「$SIGN_IDENTITY」，已退回 adhoc 签名。"
  echo "     adhoc 的 cdhash 每次重编都会变，系统会要求重新授权辅助功能。"
  echo "     想避免反复授权，先运行一次: ./Scripts/setup-dev-signing.sh"
  echo "     或用 MACEXPERT_SIGN_IDENTITY=\"你的证书名\" ./build.sh $MODE 指定其他证书。"
fi

# build 下的 .app 只是开发/打包中间产物；注销后启动台和“打开方式”不会把它当成
# 第二个 MacExpert。/Applications 里的正式版不受影响，用户手动 open 这个包时会重新注册。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
fi

echo "== 校验 =="
lipo -info "$OUT/MacExpert" | sed 's/^/  /'
vtool -show-build "$OUT/MacExpert" | grep -E "minos|sdk|platform" | sed 's/^/  /'
if [[ "$MODE" == "release" ]]; then
  # dev 钩子痕迹必须从二进制里彻底消失，否则编译期开关就没生效。
  # 开关清单不再手写：从 Sources 里扫出所有 "--xxx" 字面量和分布式通知名，
  # 以后新增钩子也会自动纳入检查。
  LEAK_PATTERNS=()
  while IFS= read -r pat; do
    [[ -n "$pat" ]] && LEAK_PATTERNS+=("$pat")
  done < <(
    {
      grep -rhoE '"--[A-Za-z0-9][A-Za-z0-9_-]*"' Sources | tr -d '"' || true
      grep -rho 'com\.slh\.macexpert\.drive' Sources || true
    } | sort -u
  )

  if (( ${#LEAK_PATTERNS[@]} == 0 )); then
    echo "  ⚠️ 没有从 Sources 扫到任何 dev 钩子字面量，检查一下 grep 规则是否失效。"
  fi

  LEAKED=0
  # 一次性取出二进制里的字符串：避免 strings | grep -q 在 pipefail 下被 SIGPIPE 干扰。
  BINARY_STRINGS="$(strings "$OUT/MacExpert")"
  for pat in "${LEAK_PATTERNS[@]}"; do
    if grep -qF -e "$pat" <<< "$BINARY_STRINGS"; then
      echo "  ❌ 发布构建里仍存在测试钩子入口: $pat"
      LEAKED=1
    fi
  done
  if (( LEAKED )); then
    echo "    别分发这个包。"
    exit 1
  fi
  echo "  ✓ 二进制中已无测试钩子入口（已检查 ${#LEAK_PATTERNS[@]} 个开关/通知名）"
fi

echo "== done =="
echo "$PWD/$APP"
if [[ "$MODE" == "dev" ]]; then
  echo "⚠️  开发构建：含 dev 钩子，任何本机进程都能经分布式通知驱动它敲键盘。"
  echo "    要发给别人请用 ./build.sh release"
else
  echo "✅ 发布构建：dev 钩子已编掉，可分发。"
fi
