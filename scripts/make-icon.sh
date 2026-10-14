#!/usr/bin/env bash
# Renders assets/AppIcon.svg into assets/AppIcon.icns. Run it after changing the SVG and commit both files.
# Needs Google Chrome for the SVG rendering (CoreSVG drops the shadows) and iconutil from Xcode's tools.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
cp "$repo_root/assets/AppIcon.svg" "$work/icon.svg"

render() { # size output
  printf '<html><body style="margin:0"><img src="icon.svg" width="%s" height="%s" style="display:block"></body></html>' \
    "$1" "$1" >"$work/page.html"
  "$chrome" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --force-device-scale-factor=1 --window-size="$1,$1" --screenshot="$2" "file://$work/page.html" >/dev/null 2>&1
}

for size in 16 32 128 256 512; do
  render "$size" "$iconset/icon_${size}x${size}.png"
  render "$((size * 2))" "$iconset/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$iconset" -o "$repo_root/assets/AppIcon.icns"
echo "Wrote $repo_root/assets/AppIcon.icns"
