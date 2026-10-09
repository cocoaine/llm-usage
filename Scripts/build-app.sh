#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Prefer the full Xcode toolchain without changing the machine's selected developer directory.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/llmusage-clang-cache"
export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/llmusage-swift-module-cache"
# The sandboxed environment can deny dsymutil's output creation. This first
# runnable, ad-hoc-signed build does not ship debug symbols.
swift build -c release --disable-sandbox --cache-path "${TMPDIR:-/tmp}/llmusage-swift-cache" -debug-info-format none
binary_dir=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "${TMPDIR:-/tmp}/llmusage-swift-cache" -debug-info-format none)
app_path="$PWD/dist/LLM Usage.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/LLMUsage" "$app_path/Contents/MacOS/LLMUsage"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
printf 'APPL????' > "$app_path/Contents/PkgInfo"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$app_path"
print "Built: $app_path"
