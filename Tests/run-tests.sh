#!/bin/zsh
# 纯单元测试：不启动 App、不碰剪贴板、不注册热键。
#
#   ./Tests/run-tests.sh      （或 ./build.sh test）
#
# 只用 Xcode Command Line Tools：把非 UI 源码和 Tests/UnitTests.swift 编成一个
# 一次性可执行文件，跑完即退。依赖真实键盘布局/焦点/时间表的内容不放在这里，
# 那些由 Tests/smoke.sh 覆盖。
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
TARGET="arm64-apple-macosx15.0"
OUT="build/tests/UnitTests"

SOURCES=(
  Sources/Core/AppState.swift
  Sources/Core/AppVersion.swift
  Sources/Core/AppLog.swift
  Sources/Core/HotkeyCenter.swift
  Sources/Core/FeatureModule.swift
  Sources/Features/TypeClip/Keymap.swift
  Sources/Features/TypeClip/TyperEngine.swift
  Sources/Features/TypeClip/TypeClipFeature.swift
  Sources/Features/TypeClip/TypeClipFeature+Module.swift
  Sources/Features/Shared/EventInjector.swift
  Sources/Features/Shared/TimelinePlayer.swift
  Sources/Features/KeyMapping/KeyMapping.swift
  Sources/Features/KeyMapping/MouseButtonTap.swift
  Sources/Features/KeyMapping/ShortcutSender.swift
  Sources/Features/KeyMapping/KeyMappingFeature.swift
  Sources/Features/KeyMapping/KeyMappingFeature+Module.swift
  Sources/Features/KeyMapping/KeyMappingEditorModel.swift
  Sources/Features/SmoothScroll/SmoothScrollSample.swift
  Sources/Features/SmoothScroll/SmoothScrollEngine.swift
  Sources/Features/SmoothScroll/SmoothScrollStore.swift
  Sources/Features/SmoothScroll/ScrollAcceleration.swift
  Sources/Features/SmoothScroll/ScrollTap.swift
  Sources/Features/SmoothScroll/ScrollPoster.swift
  Sources/Features/SmoothScroll/SmoothScrollFeature.swift
  Sources/Features/SmoothScroll/SmoothScrollFeature+Module.swift
  Sources/Features/Translation/TranslationModels.swift
  Sources/Features/Translation/TranslationClassifier.swift
  Sources/Features/Translation/TranslationPrompt.swift
  Sources/Features/Translation/TranslationSSE.swift
  Sources/Features/Translation/TranslationProvider.swift
  Sources/Features/Translation/TranslationClient.swift
  Sources/Features/Translation/TranslationFeature.swift
  Sources/Features/Translation/TranslationFeature+Module.swift
  Tests/UnitTests.swift
)

for file in "${SOURCES[@]}"; do
  [[ -f "$file" ]] || { echo "❌ 缺少源码: $file" >&2; exit 1; }
done

mkdir -p build/tests
echo "== 编译单元测试 ($TARGET) =="
swiftc -Onone -swift-version 5 -target "$TARGET" -sdk "$SDK" \
  -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$SDK_VERSION" \
  "${SOURCES[@]}" -o "$OUT"

echo "== 运行单元测试 =="
"$OUT"
