#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/llmusage-clang-cache"
export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/llmusage-swift-module-cache"

source_image="${1:-Resources/AppIcon.png}"
iconset_path="Resources/AppIcon.iconset"
output_path="Resources/AppIcon.icns"

if [[ ! -f "$source_image" ]]; then
    print -u2 "Missing source image: $source_image"
    exit 1
fi

if ! command -v iconutil >/dev/null || ! command -v sips >/dev/null; then
    print -u2 "build-icon.sh requires macOS sips and iconutil."
    exit 1
fi

rm -rf "$iconset_path"
mkdir -p "$iconset_path"

function render_icon() {
    local size="$1"
    local name="$2"
    sips -z "$size" "$size" "$source_image" --out "$iconset_path/$name" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

if ! iconutil -c icns "$iconset_path" -o "$output_path" 2>/dev/null; then
    # iconutil on the current macOS beta can reject otherwise valid PNG iconsets.
    # ICNS accepts its standard PNG representations directly, so retain a local,
    # deterministic fallback for packaging builds.
    swift - "$iconset_path" "$output_path" <<'SWIFT'
import Foundation

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

let arguments = CommandLine.arguments
let iconset = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let representations = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

var chunks = Data()
for (type, filename) in representations {
    let image = try Data(contentsOf: iconset.appendingPathComponent(filename))
    chunks.append(type.data(using: .macOSRoman)!)
    appendUInt32(UInt32(image.count + 8), to: &chunks)
    chunks.append(image)
}

var icns = Data("icns".utf8)
appendUInt32(UInt32(chunks.count + 8), to: &icns)
icns.append(chunks)
try icns.write(to: output, options: .atomic)
SWIFT
fi
print "Built: $output_path"
