#!/bin/sh
# Download the latest Codex CLI + code-mode-host archives for every supported
# platform into bin/<platform>/. Requires curl or wget. No jq needed.
# Invoke as: sh setup.sh   (USB may be VFAT — do not rely on ./setup.sh)
set -eu

SOURCE=$0
while [ -h "$SOURCE" ]; do
  SCRIPT_DIR=$(CDPATH= cd -P -- "$(dirname -- "$SOURCE")" && pwd)
  SOURCE=$(readlink -- "$SOURCE")
  case $SOURCE in
    /*) ;;
    *) SOURCE=$SCRIPT_DIR/$SOURCE ;;
  esac
done
SCRIPT_DIR=$(CDPATH= cd -P -- "$(dirname -- "$SOURCE")" && pwd)
BIN_ROOT=$SCRIPT_DIR/bin
RELEASE_BASE=https://github.com/openai/codex/releases/latest/download

OS=$(uname -s 2>/dev/null || echo unknown)
ARCH=$(uname -m 2>/dev/null || echo unknown)
echo "Host: $OS / $ARCH"
echo "Downloading latest Codex release assets for all platforms into:"
echo "  $BIN_ROOT"
echo

if command -v curl >/dev/null 2>&1; then
  fetch() {
    curl -fL --progress-bar -o "$2" "$1"
  }
elif command -v wget >/dev/null 2>&1; then
  fetch() {
    wget -O "$2" "$1"
  }
else
  echo "Error: need curl or wget to download release assets." >&2
  exit 1
fi

download() {
  url=$1
  dest=$2
  mkdir -p "$(dirname -- "$dest")"
  echo "→ $(basename "$dest")"
  echo "  from $url"
  fetch "$url" "$dest"
}

# Each line: platform|remote_codex_stem|local_codex|remote_host_stem|local_host
# Remote stems match openai/codex release asset names (without .tar.gz).
# Local names match what launch.sh / launch.bat expect.
PLATFORMS="
linux-x64|codex-x86_64-unknown-linux-musl|codex-linux-x64.tar.gz|codex-code-mode-host-x86_64-unknown-linux-musl|codex-code-mode-host-linux-x64.tar.gz
macos-x64|codex-x86_64-apple-darwin|codex-macos-x64.tar.gz|codex-code-mode-host-x86_64-apple-darwin|codex-code-mode-host-macos-x64.tar.gz
macos-arm64|codex-aarch64-apple-darwin|codex-macos-arm64.tar.gz|codex-code-mode-host-aarch64-apple-darwin|codex-code-mode-host-macos-arm64.tar.gz
windows-x64|codex-x86_64-pc-windows-msvc.exe|codex-windows-x64.tar.gz|codex-code-mode-host-x86_64-pc-windows-msvc.exe|codex-code-mode-host-windows-x64.tar.gz
"

DOWNLOADED=""

# Portable line iteration (no process-substitution / bashisms).
OLDIFS=$IFS
IFS='
'
for entry in $PLATFORMS; do
  IFS=$OLDIFS
  case $entry in
    ''|\#*) continue ;;
  esac

  platform=${entry%%|*}
  rest=${entry#*|}
  remote_codex=${rest%%|*}
  rest=${rest#*|}
  local_codex=${rest%%|*}
  rest=${rest#*|}
  remote_host=${rest%%|*}
  local_host=${rest#*|}

  echo "=== $platform ==="
  download "$RELEASE_BASE/${remote_codex}.tar.gz" "$BIN_ROOT/$platform/$local_codex"
  DOWNLOADED="$DOWNLOADED
  $platform/$local_codex"
  download "$RELEASE_BASE/${remote_host}.tar.gz" "$BIN_ROOT/$platform/$local_host"
  DOWNLOADED="$DOWNLOADED
  $platform/$local_host"
  echo
  IFS='
'
done
IFS=$OLDIFS

echo "========================================"
echo "Setup complete. Downloaded into:"
echo "$DOWNLOADED"
echo
echo "You can now launch with:"
echo "  sh launch.sh          (Linux / macOS)"
echo "  launch.bat            (Windows)"
echo "Archives stay on the USB; the launcher extracts them to host temp on first run."
