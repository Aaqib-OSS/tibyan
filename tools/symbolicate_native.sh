#!/usr/bin/env bash
# Reads libflutter.so frames from a GlitchTip native crash by hand.
#
#   tools/symbolicate_native.sh [--engine <hash>] [--abi arm64|arm|x64] <offset>...
#
# An offset is a frame's instruction_addr minus its image_addr (both in the
# event's JSON), e.g. 0x50efb8. The engine defaults to this SDK's
# bin/internal/engine.version (the release must have been built with the
# same Flutter). Frames print in the order given; GlitchTip lists the
# crashing frame last.
#
# Needs the Android NDK (llvm-addr2line). Engine symbols are cached in
# ~/.cache/tibyan/engine-symbols (shared with tools/upload_symbols.sh).
set -euo pipefail

ENGINE=""
ABI=arm64
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --engine) ENGINE="$2"; shift 2 ;;
    --abi) ABI="$2"; shift 2 ;;
    *) echo "Unknown option $1" >&2; exit 1 ;;
  esac
done
[ $# -gt 0 ] || { sed -n '2,13p' "$0"; exit 1; }

if [ -z "$ENGINE" ]; then
  ENGINE="$(cat "$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")/bin/internal/engine.version")"
fi
[[ "$ENGINE" =~ ^[0-9a-f]{40}$ ]] || { echo "Bad engine hash: $ENGINE" >&2; exit 1; }

DIR="$HOME/.cache/tibyan/engine-symbols/$ENGINE/android-$ABI-release"
if [ ! -f "$DIR/libflutter.so" ]; then
  mkdir -p "$DIR"
  curl -fsSL -o "$DIR/symbols.zip" \
    "https://storage.googleapis.com/flutter_infra_release/flutter/$ENGINE/android-$ABI-release/symbols.zip"
  unzip -oq "$DIR/symbols.zip" -d "$DIR"
  rm -f "$DIR/symbols.zip"
fi

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
A2L="$(ls -d "$SDK"/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-addr2line 2>/dev/null | sort | tail -1)"
[ -x "$A2L" ] || A2L="$(command -v llvm-addr2line || true)"
[ -n "$A2L" ] || { echo "llvm-addr2line not found (install the NDK)." >&2; exit 1; }

echo "engine $ENGINE ($ABI)"
for off in "$@"; do
  printf '%s  ' "$off"
  "$A2L" -Cfp -e "$DIR/libflutter.so" "$off" | sed 's# at .*/flutter/# at flutter/#'
done
