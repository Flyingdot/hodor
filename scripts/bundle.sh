#!/usr/bin/env bash
# Builds build/Tunneler.app from the Swift package.
# Usage: scripts/bundle.sh [--install]
#   --install  also copy the app to ~/Applications (replaces an existing copy)
set -euo pipefail

install=false
for arg in "$@"; do
  case "$arg" in
    --install) install=true ;;
    -h|--help) echo "Usage: $0 [--install]"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; echo "Usage: $0 [--install]" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"

app="build/Tunneler.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/Tunneler" "$app/Contents/MacOS/Tunneler"
cp scripts/Info.plist "$app/Contents/Info.plist"

codesign --force --sign - "$app"

echo "Built $repo_root/$app"

if [ "$install" = true ]; then
  if pgrep -x Tunneler >/dev/null; then
    echo "Tunneler is running. Quit it from the menu bar, then run $0 --install again." >&2
    exit 1
  fi
  dest="$HOME/Applications/Tunneler.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$dest"
  cp -R "$app" "$dest"
  echo "Installed $dest"
fi
