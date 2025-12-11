#!/usr/bin/env bash

set -eou pipefail

# Usage:
#   ./run.sh [playbook.yml|playbooks/<file>.yml|/abs/path.yml] [ansible-playbook args]
#   ./run.sh bootstrap [--user <ssh_user>] [--pubkey <pubkey_path>] [ansible args]
# Notes:
# - Normal mode: If the first argument does not start with '-', it is treated as the playbook to run.
# - Default playbook: playbooks/ping.yml
# - Bootstrap mode: one-time helper that installs your SSH public key using password auth.
#   • Defaults: --user alarm, --pubkey ~/.ssh/id_ed25519_local.pub
#   • Always adds -k (ask SSH password) and disables host key checking for this run only
#   • Passes through any extra Ansible args (e.g., --limit, -v/-vvv)
# - Script is location-independent: you can run it from anywhere, e.g.:
#     ansible-home-cluster/run.sh ping.yml -vvv
#     ./run.sh playbooks/ping.yml --limit rpi5b16g1
#     ./run.sh bootstrap --user alarm --pubkey ~/.ssh/id_ed25519_local.pub --limit rpi5b16g1 -vv
# - Verbosity flags (-v/-vv/-vvv/-vvvv) and all other ansible-playbook options are passed through as-is.

# Resolve script directory to build absolute paths regardless of current working directory
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

INVENTORY="$SCRIPT_DIR/inventories/inventory.yml"
PLAYBOOKS_DIR="$SCRIPT_DIR/playbooks"

# Ensure Ansible uses this project's config (for roles_path, etc.) regardless of CWD
if [[ -f "$SCRIPT_DIR/ansible.cfg" ]]; then
  export ANSIBLE_CONFIG="$SCRIPT_DIR/ansible.cfg"
fi

PLAYBOOK="ping.yml"

if [[ ${1-} && "$1" != -* ]]; then
  PLAYBOOK="$1"
  shift
fi

# Bootstrap subcommand: install public key to targets using password auth
if [[ "${PLAYBOOK}" == "bootstrap" ]]; then
  # Defaults
  BOOTSTRAP_USER="alarm"
  BOOTSTRAP_PUBKEY="$HOME/.ssh/id_ed25519_local.pub"

  # Parse subcommand options: --user, --pubkey (stop at first non-option to allow passing Ansible flags)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        BOOTSTRAP_USER="$2"; shift 2 ;;
      --pubkey)
        BOOTSTRAP_PUBKEY="$2"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  if [[ ! -f "$BOOTSTRAP_PUBKEY" ]]; then
    echo "Error: public key file not found: $BOOTSTRAP_PUBKEY" >&2
    exit 2
  fi

  PLAYBOOK_PATH="$PLAYBOOKS_DIR/bootstrap.yml"
  if [[ ! -f "$PLAYBOOK_PATH" ]]; then
    echo "Error: bootstrap playbook not found: $PLAYBOOK_PATH" >&2
    echo "Please ensure playbooks/bootstrap.yml exists." >&2
    exit 3
  fi

  echo "Using BOOTSTRAP mode"
  echo " - SSH user: $BOOTSTRAP_USER"
  echo " - Public key: $BOOTSTRAP_PUBKEY"
  echo "Using playbook: $PLAYBOOK_PATH"
  echo "Using inventory: $INVENTORY"

  # Build common args
  EXTRA_VARS=(
    -e "bootstrap_user=$BOOTSTRAP_USER"
    -e "bootstrap_pubkey=$BOOTSTRAP_PUBKEY"
    -e "ansible_user=$BOOTSTRAP_USER"
  )

  if command -v uv >/dev/null 2>&1; then
    echo "Running via uv (using project-managed dependencies)"
    ANSIBLE_HOST_KEY_CHECKING=False \
      uv run ansible-playbook \
        -i "$INVENTORY" \
        "$PLAYBOOK_PATH" \
        -k \
        "${EXTRA_VARS[@]}" \
        "$@"
  else
    ANSIBLE_HOST_KEY_CHECKING=False \
      ansible-playbook \
        -i "$INVENTORY" \
        "$PLAYBOOK_PATH" \
        -k \
        "${EXTRA_VARS[@]}" \
        "$@"
  fi
  exit 0
fi

# Determine the full playbook path
case "$PLAYBOOK" in
  /*)
    PLAYBOOK_PATH="$PLAYBOOK" # absolute path provided
    ;;
  playbooks/*)
    PLAYBOOK_PATH="$SCRIPT_DIR/$PLAYBOOK" # relative path under playbooks provided
    ;;
  *)
    PLAYBOOK_PATH="$PLAYBOOKS_DIR/$PLAYBOOK" # just a file name; assume under playbooks/
    ;;
esac

if [[ ! -f "$PLAYBOOK_PATH" ]]; then
  echo "Error: playbook not found: $PLAYBOOK_PATH" >&2
  exit 1
fi

echo "Using playbook: $PLAYBOOK_PATH"
echo "Using inventory: $INVENTORY"

if command -v uv >/dev/null 2>&1; then
  echo "Running via uv (using project-managed dependencies)"
  uv run ansible-playbook \
    -i "$INVENTORY" \
    "$PLAYBOOK_PATH" \
    "$@"
else
  ansible-playbook \
    -i "$INVENTORY" \
    "$PLAYBOOK_PATH" \
    --ask-vault-pass \
    "$@"
fi
