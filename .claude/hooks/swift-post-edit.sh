#!/usr/bin/env bash
# PostToolUse hook: formats the edited .swift file, then builds and reports compile errors to Claude (exit 2).
f="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')"
case "$f" in *.swift) ;; *) exit 0 ;; esac
[ -f "$f" ] || exit 0

root="$(cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" && pwd -P)" || exit 0
case "$(cd "$(dirname "$f")" && pwd -P)/" in "$root"/*) ;; *) exit 0 ;; esac
cd "$root" || exit 0
swift format -i "$f"

if ! out="$(swift build 2>&1)"; then
    echo "swift build failed after editing $f:" >&2
    sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$out" | grep -E '^/.+:[0-9]+:[0-9]+: error:' | sort -u | head -20 >&2
    exit 2
fi
