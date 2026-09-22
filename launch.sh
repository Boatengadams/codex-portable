#!/bin/sh
# Portable launcher for Linux and macOS.
# USB is VFAT — binaries live as .tar.gz on the stick and are extracted to
# host temp (where chmod +x works). Invoke as: sh launch.sh  (not ./launch.sh)
# Optional first argument: an existing account name under accounts/<name>/.
# Use --switch to pick another account anytime (sessions stay saved per profile).
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

LAST_ACCOUNT_FILE=$ACCOUNTS_DIR/.last-account

validate_account_name() {
  case $1 in
    ''|*/*|*\\*|.|..|*".."*) return 1 ;;
    *) return 0 ;;
  esac
}

is_saved_account_dir() {
  base=$(basename "$1")
  case $base in
    .*) return 1 ;;
  esac
  [ -d "$1" ]
}

list_accounts() {
  any=0
  last=
  if [ -f "$LAST_ACCOUNT_FILE" ]; then
    last=$(tr -d '\r\n' < "$LAST_ACCOUNT_FILE" 2>/dev/null || true)
  fi
  for d in "$ACCOUNTS_DIR"/*; do
    is_saved_account_dir "$d" || continue
    name=$(basename "$d")
    suffix=
    if [ -n "$last" ] && [ "$name" = "$last" ]; then
      suffix=' (last used — sessions saved here)'
    fi
    echo "  $name$suffix"
    any=1
  done
  if [ "$any" -eq 0 ]; then
    echo "  (none)"
  fi
}

confirm_and_delete_account() {
  del_name=$1
  if ! validate_account_name "$del_name"; then
    echo "Invalid account name: $del_name" >&2
    return 1
  fi
  del_dir=$ACCOUNTS_DIR/$del_name
  if [ ! -d "$del_dir" ]; then
    echo "Account not found: $del_name" >&2
    echo "Available accounts:" >&2
    list_accounts >&2
    return 1
  fi
  echo "WARNING: This permanently deletes the local login/session for"
  echo "account \"$del_name\" on this USB."
  echo "The account on OpenAI's side is NOT affected — only this USB's"
  echo "saved credentials and Codex session history for this profile."
  echo "Folder to delete: $del_dir"
  printf "Type the account name again to confirm deletion: "
  read -r confirm || true
  if [ "$confirm" != "$del_name" ]; then
    echo "Confirmation did not match. Deletion cancelled; no changes made."
    return 1
  fi
  rm -rf -- "$del_dir"
  if [ -f "$LAST_ACCOUNT_FILE" ] && [ "$(tr -d '\r\n' < "$LAST_ACCOUNT_FILE")" = "$del_name" ]; then
    rm -f -- "$LAST_ACCOUNT_FILE"
  fi
  echo "Deleted account \"$del_name\" ($del_dir)."
  return 0
}

interactive_delete_account() {
  echo "Choose an account to delete:"
  account_count=0
  for d in "$ACCOUNTS_DIR"/*; do
    is_saved_account_dir "$d" || continue
    account_count=$((account_count + 1))
    eval "DELETE_ACCOUNT_$account_count=$(basename "$d")"
    echo "  $account_count) $(basename "$d")"
  done
  if [ "$account_count" -eq 0 ]; then
    echo "  (none)"
    return 0
  fi
  printf "Account number to delete (or Enter to cancel): "
  read -r pick || true
  case $pick in
    ''|*[!0-9]*)
      echo "Deletion cancelled."
      return 0
      ;;
  esac
  if [ "$pick" -lt 1 ] 2>/dev/null || [ "$pick" -gt "$account_count" ] 2>/dev/null; then
    echo "No saved account matches that selection."
    return 0
  fi
  eval "del_name=\$DELETE_ACCOUNT_$pick"
  confirm_and_delete_account "$del_name" || true
}

choose_account_interactive() {
  while :; do
    last_hint=
    if [ -f "$LAST_ACCOUNT_FILE" ]; then
      last_hint=$(tr -d '\r\n' < "$LAST_ACCOUNT_FILE" 2>/dev/null || true)
    fi
    echo "Saved accounts (each keeps its own Codex sessions on this USB):"
    if [ -n "$last_hint" ]; then
      echo "  Last used profile: $last_hint"
    fi
    account_count=0
    for d in "$ACCOUNTS_DIR"/*; do
      is_saved_account_dir "$d" || continue
      account_count=$((account_count + 1))
      name=$(basename "$d")
      marker=
      if [ -n "$last_hint" ] && [ "$name" = "$last_hint" ]; then
        marker=' *'
      fi
      echo "  $account_count) $name$marker"
    done
    if [ "$account_count" -eq 0 ]; then
      echo "  (none)"
    fi
    echo "  n) Sign in with a new account"
    echo "  d) Delete a saved account"
    printf "Choose a saved account, n, or d: "
    read -r choice || true

    case $choice in
      d|D|delete|DELETE)
        interactive_delete_account
        continue
        ;;
      n|N|new|NEW)
        NEW_LOGIN=1
        printf "Name for this saved account: "
        read -r ACCOUNT || true
        if ! validate_account_name "$ACCOUNT"; then
          echo "Invalid account name: $ACCOUNT" >&2
          exit 1
        fi
        if [ -e "$ACCOUNTS_DIR/$ACCOUNT" ]; then
          echo "An account named \"$ACCOUNT\" already exists. Choose it from the saved accounts list." >&2
          exit 1
        fi
        return 0
        ;;
      *[!0-9]*|'')
        echo "No valid account selected." >&2
        exit 1
        ;;
      *)
        selected=0
        current=0
        for d in "$ACCOUNTS_DIR"/*; do
          is_saved_account_dir "$d" || continue
          current=$((current + 1))
          if [ "$current" -eq "$choice" ]; then
            ACCOUNT=$(basename "$d")
            selected=1
            break
          fi
        done
        if [ "$selected" -ne 1 ]; then
          echo "No saved account matches that selection." >&2
          exit 1
        fi
        return 0
        ;;
    esac
  done
}

record_account_handoff() {
  account=$1
  home=$2
  printf '%s\n' "$account" > "$LAST_ACCOUNT_FILE"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$home/.portable-last-launch" 2>/dev/null || true
  pwd > "$home/.portable-last-cwd" 2>/dev/null || true
}

run_codex_for_account() {
  if [ "$NEW_LOGIN" -eq 0 ] && [ "$FRESH" -eq 0 ] && [ "$RESUME_LAST" -eq 0 ] && [ $# -eq 0 ] && [ -t 0 ]; then
    if [ -f "$CODEX_HOME/.portable-last-cwd" ]; then
      last_cwd=$(tr -d '\r\n' < "$CODEX_HOME/.portable-last-cwd" 2>/dev/null || true)
      if [ -n "$last_cwd" ] && [ -d "$last_cwd" ]; then
        echo "Last workspace for $ACCOUNT: $last_cwd"
      fi
    fi
    printf 'Continue where you left off on \"%s\"? [Y=resume last session / n=new / p=pick session]: ' "$ACCOUNT"
    read -r resume_choice || true
    case ${resume_choice:-Y} in
      n|N|no|NO)
        exec "$CODEX"
        ;;
      p|P|pick|picker)
        exec "$CODEX" resume
        ;;
      *)
        exec "$CODEX" resume --last
        ;;
    esac
  fi
  if [ "$RESUME_LAST" -eq 1 ] && [ $# -eq 0 ]; then
    exec "$CODEX" resume --last
  fi
  exec "$CODEX" "$@"
}

# --delete / --remove is a standalone action; never combined with launch.
case ${1-} in
  --delete|--remove)
    if [ -z "${2-}" ]; then
      echo "Usage: sh launch.sh --delete <account-name>" >&2
      exit 1
    fi
    confirm_and_delete_account "$2" || exit 1
    exit 0
    ;;
esac

FRESH=0
RESUME_LAST=0
FORCE_MENU=0
while [ $# -gt 0 ]; do
  case $1 in
    --fresh)
      FRESH=1
      shift
      ;;
    --resume-last)
      RESUME_LAST=1
      shift
      ;;
    --switch)
      FORCE_MENU=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Try: sh launch.sh [--switch] [--fresh|--resume-last] [account] [codex args...]" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

ACCOUNT=${1-}
NEW_LOGIN=0
if [ "$FORCE_MENU" -eq 1 ]; then
  ACCOUNT=
fi

if [ -n "$ACCOUNT" ]; then
  shift
  if ! validate_account_name "$ACCOUNT" || ! is_saved_account_dir "$ACCOUNTS_DIR/$ACCOUNT"; then
    echo "Stored account not found: $ACCOUNT" >&2
    echo "Use sh launch.sh or sh launch.sh --switch to sign in, select, or delete an account." >&2
    exit 1
  fi
else
  choose_account_interactive
fi

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

if [ "$NEW_LOGIN" -eq 1 ]; then
  # Use a temporary profile so a cancelled/failed login never appears as saved.
  LOGIN_HOME=$ACCOUNTS_DIR/.login-$$
  trap 'rm -rf -- "$LOGIN_HOME"' EXIT HUP INT TERM
  mkdir -p "$LOGIN_HOME"
  printf '%s\n' 'cli_auth_credentials_store = "file"' > "$LOGIN_HOME/config.toml"
  export CODEX_HOME=$LOGIN_HOME
  echo "Starting Codex sign-in for profile: $ACCOUNT"
  if ! "$CODEX" login; then
    echo "Login was not completed; no account was saved." >&2
    exit 1
  fi
  if [ ! -s "$LOGIN_HOME/auth.json" ]; then
    echo "Login finished but no portable credential file was created; no account was saved." >&2
    exit 1
  fi
  mv "$LOGIN_HOME" "$ACCOUNTS_DIR/$ACCOUNT"
  trap - EXIT HUP INT TERM
  echo "Saved account: $ACCOUNT"
fi

export CODEX_HOME=$ACCOUNTS_DIR/$ACCOUNT
if ! is_saved_account_dir "$CODEX_HOME"; then
  echo "Stored account not found: $ACCOUNT" >&2
  exit 1
fi
echo "Using account: $ACCOUNT ($CODEX_HOME)"
echo "Tip: exit Codex anytime and run \"sh launch.sh --switch\" to change profile; sessions stay in that profile folder."
record_account_handoff "$ACCOUNT" "$CODEX_HOME"

run_codex_for_account "$@"
