#!/bin/sh
# Portable launcher for Linux and macOS.
# USB is VFAT — binaries live as .tar.gz on the stick and are extracted to
# host temp (where chmod +x works). Invoke as: sh launch.sh  (not ./launch.sh)
# Optional first argument: account name under accounts/<name>/
set -eu

# Resolve this script's path even when it is invoked through one or more symlinks.
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

ACCOUNTS_DIR=$SCRIPT_DIR/accounts
mkdir -p "$ACCOUNTS_DIR"

list_accounts() {
  any=0
  for d in "$ACCOUNTS_DIR"/*; do
    [ -d "$d" ] || continue
    echo "  $(basename "$d")"
    any=1
  done
  if [ "$any" -eq 0 ]; then
    echo "  (none)"
  fi
}

# --delete / --remove is a standalone action; never combined with launch.
case ${1-} in
  --delete|--remove)
    DEL_NAME=${2-}
    if [ -z "$DEL_NAME" ]; then
      echo "Usage: sh launch.sh --delete <account-name>" >&2
      exit 1
    fi
    case $DEL_NAME in
      ''|*/*|*\\*|.|..|*".."*)
        echo "Invalid account name: $DEL_NAME" >&2
        exit 1
        ;;
    esac
    DEL_DIR=$ACCOUNTS_DIR/$DEL_NAME
    if [ ! -d "$DEL_DIR" ]; then
      echo "Account not found: $DEL_NAME" >&2
      echo "Available accounts:" >&2
      list_accounts >&2
      exit 1
    fi
    echo "WARNING: This permanently deletes the local login/session for"
    echo "account \"$DEL_NAME\" on this USB."
    echo "The account on OpenAI's side is NOT affected — only this USB's"
    echo "saved credentials for it will be removed."
    echo "Folder to delete: $DEL_DIR"
    printf "Type the account name again to confirm deletion: "
    read -r CONFIRM || true
    if [ "$CONFIRM" != "$DEL_NAME" ]; then
      echo "Confirmation did not match. Deletion cancelled; no changes made."
      exit 1
    fi
    rm -rf -- "$DEL_DIR"
    echo "Deleted account \"$DEL_NAME\" ($DEL_DIR)."
    exit 0
    ;;
esac

ACCOUNT=${1-}
if [ -n "$ACCOUNT" ]; then
  shift
else
  echo "Available accounts:"
  any=0
  for d in "$ACCOUNTS_DIR"/*; do
    [ -d "$d" ] || continue
    echo "  $(basename "$d")"
    any=1
  done
  if [ "$any" -eq 0 ]; then
    echo "  (none yet — type a name to create one)"
  fi
  printf "Enter account name (existing or new): "
  # stdin may be a pipe in tests; keep portable read
  read -r ACCOUNT || true
  if [ -z "$ACCOUNT" ]; then
    echo "No account selected." >&2
    exit 1
  fi
fi

case $ACCOUNT in
  ''|*/*|*\\*|.|..|*".."*)
    echo "Invalid account name: $ACCOUNT" >&2
    exit 1
    ;;
esac

OS=$(uname -s)
ARCH=$(uname -m)
case $OS in
  Linux)
    case $ARCH in
      x86_64|amd64) PLATFORM=linux-x64 ;;
      *) echo "Unsupported Linux architecture: $ARCH" >&2; exit 1 ;;
    esac
    ;;
  Darwin)
    case $ARCH in
      x86_64) PLATFORM=macos-x64 ;;
      arm64|aarch64) PLATFORM=macos-arm64 ;;
      *) echo "Unsupported macOS architecture: $ARCH" >&2; exit 1 ;;
    esac
    ;;
  *) echo "Unsupported operating system: $OS" >&2; exit 1 ;;
esac

BIN_DIR=$SCRIPT_DIR/bin/$PLATFORM
EXTRACT_DIR=${TMPDIR:-/tmp}/codexportable-$PLATFORM
CODEX=$EXTRACT_DIR/codex
HOST=$EXTRACT_DIR/codex-code-mode-host
CODEX_ARCHIVE=$BIN_DIR/codex-$PLATFORM.tar.gz
HOST_ARCHIVE=$BIN_DIR/codex-code-mode-host-$PLATFORM.tar.gz

if [ ! -f "$CODEX_ARCHIVE" ] || [ ! -f "$HOST_ARCHIVE" ]; then
  echo "Codex archives are incomplete in: $BIN_DIR" >&2
  exit 1
fi

if [ ! -f "$CODEX" ] || [ ! -f "$HOST" ]; then
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$CODEX_ARCHIVE" -C "$EXTRACT_DIR"
  tar -xzf "$HOST_ARCHIVE" -C "$EXTRACT_DIR"

  # Archives unpack with platform-specific names; normalize for the host sibling check.
  for f in "$EXTRACT_DIR"/codex-*; do
    [ -f "$f" ] || continue
    case $f in
      */codex-code-mode-host*) continue ;;
      *) mv "$f" "$CODEX" ;;
    esac
  done
  for f in "$EXTRACT_DIR"/codex-code-mode-host*; do
    [ -f "$f" ] || continue
    mv "$f" "$HOST"
  done
fi

if [ ! -f "$CODEX" ] || [ ! -f "$HOST" ]; then
  echo "Failed to prepare Codex binaries in: $EXTRACT_DIR" >&2
  exit 1
fi

chmod +x "$CODEX" "$HOST"

export CODEX_HOME=$ACCOUNTS_DIR/$ACCOUNT
mkdir -p "$CODEX_HOME"
echo "Using account: $ACCOUNT ($CODEX_HOME)"

exec "$CODEX" "$@"
