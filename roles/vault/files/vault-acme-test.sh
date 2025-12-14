#!/usr/bin/env sh

# Helper to exercise Vault ACME using a real ACME client in Docker.
#
# Primary client: acme.sh (official image/entrypoint)
# Optional client: lego (goacme/lego) via --client lego
#
# Usage (sensible defaults):
#   vault-acme-test.sh <domain>
#       [--server <acme_dir_url>] [--email <addr>] [--alpn | --http-01]
#       [--state-dir <path>] [--ca <host_ca_bundle_path>] [--client acme.sh|lego]
#       [--deploy-to <container>] [--verbose]
#
# Defaults:
#   --server     -> https://${VAULT_ACME_HOST:-127.0.0.1}:${VAULT_ACME_PORT:-8200}/v1/pki/acme/directory
#   --email      -> noreply@$(hostname -d || echo homelab)
#   Challenge    -> TLS-ALPN-01 by default (requires port 443 free). Use --http-01 for HTTP-01 on port 80.
#   --state-dir  -> $HOME/.acme-test
#   --ca         -> auto-detect: /etc/ssl/cert.pem, /etc/ssl/certs/ca-certificates.crt, /etc/ssl/certs/ca-bundle.crt
#
# Notes:
# - Uses host networking to reach Vault at the configured ACME directory.
# - Mounts the host CA bundle into the container and sets SSL_CERT_FILE to trust Vault TLS (avoids curl 60).
# - Requires Docker on the host.

set -eu

color() {
  # $1 type: info|ok|warn|err, $2 message
  if command -v tput >/dev/null 2>&1; then
    case "$1" in
      info) printf "\033[36m[INFO]\033[0m %s\n" "$2" ;;
      ok)   printf "\033[32m[ OK ]\033[0m %s\n" "$2" ;;
      warn) printf "\033[33m[WARN]\033[0m %s\n" "$2" ;;
      err)  printf "\033[31m[ERR ]\033[0m %s\n" "$2" ;;
      *)    printf "%s\n" "$2" ;;
    esac
  else
    printf "%s: %s\n" "$1" "$2"
  fi
}

usage() {
  cat >&2 <<EOF
Usage: $0 <domain>
  [--server <acme_dir_url>] [--email <addr>] [--alpn | --http-01]
  [--state-dir <path>] [--ca <host_ca_bundle_path>] [--client acme.sh|lego]
  [--deploy-to <container>] [--verbose]

Examples:
  $0 primary.pihole.example.lan --server https://192.168.0.13:8200/v1/pki/acme/directory --email noreply@example.lan --alpn
  $0 primary.pihole.example.lan --server https://192.168.0.13:8200/v1/pki/acme/directory --http-01
EOF
}

DOMAIN=""
ACME_DIR=""
EMAIL=""
USE_ALPN=1
USE_HTTP01=0
STATE_DIR="${HOME}/.acme-test"
HOST_CA_BUNDLE="${VAULT_CA_BUNDLE:-}"
VERBOSE=0
CLIENT="acme.sh"
DEPLOY_TO=""

# Positional domain + flags
if [ "${1:-}" = "" ]; then usage; exit 2; fi
DOMAIN="$1"; shift || true

while [ $# -gt 0 ]; do
  case "$1" in
    --server)
      ACME_DIR="$2"; shift 2 ;;
    --email)
      EMAIL="$2"; shift 2 ;;
    --http-port)
      echo "[WARN] --http-port is deprecated. HTTP-01 requires port 80 by ACME spec; ignoring custom port." >&2; shift 2 ;;
    --alpn)
      USE_ALPN=1; USE_HTTP01=0; shift ;;
    --http-01)
      USE_HTTP01=1; USE_ALPN=0; shift ;;
    --state-dir)
      STATE_DIR="$2"; shift 2 ;;
    --ca)
      HOST_CA_BUNDLE="$2"; shift 2 ;;
    --client)
      CLIENT="$2"; shift 2 ;;
    --deploy-to)
      DEPLOY_TO="$2"; shift 2 ;;
    --verbose|-v)
      VERBOSE=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      color warn "Unknown option: $1"; usage; exit 2 ;;
  esac
done

# Defaults
if [ -z "$ACME_DIR" ]; then
  ACME_HOST="${VAULT_ACME_HOST:-127.0.0.1}"
  ACME_PORT="${VAULT_ACME_PORT:-8200}"
  ACME_DIR="https://${ACME_HOST}:${ACME_PORT}/v1/pki/acme/directory"
fi

if [ -z "$EMAIL" ]; then
  DOMAIN_PART=$(hostname -d 2>/dev/null || true)
  # Some systems print "(none)" when no domain is set; sanitize to empty
  if [ "$DOMAIN_PART" = "(none)" ]; then DOMAIN_PART=""; fi
  [ -z "$DOMAIN_PART" ] && DOMAIN_PART="homelab"
  EMAIL="noreply@${DOMAIN_PART}"
fi

# Detect host CA bundle if not provided
if [ -z "$HOST_CA_BUNDLE" ]; then
  for p in /etc/ssl/cert.pem /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-bundle.crt ; do
    if [ -f "$p" ]; then HOST_CA_BUNDLE="$p"; break; fi
  done
fi

if [ ! -f "$HOST_CA_BUNDLE" ]; then
  color err "Host CA bundle not found. Provide with --ca <path> or set VAULT_CA_BUNDLE. Tried: /etc/ssl/cert.pem, /etc/ssl/certs/ca-certificates.crt, /etc/ssl/certs/ca-bundle.crt";
  exit 3
fi

if ! command -v docker >/dev/null 2>&1; then
  color err "Docker is required to run this test."; exit 4
fi

mkdir -p "$STATE_DIR"

CONTAINER_CA="/etc/ssl/certs/host-ca-bundle.pem"

color info "Using ACME directory: $ACME_DIR"
color info "Account email: $EMAIL"
if [ "$USE_ALPN" -eq 1 ]; then
  color info "Challenge: TLS-ALPN-01 on port 443"
else
  color info "Challenge: HTTP-01 on port 80"
fi
color info "State dir: $STATE_DIR"
color info "Host CA bundle: $HOST_CA_BUNDLE (mounted to $CONTAINER_CA)"
color info "Client: $CLIENT"

# Preflight checks
if [ "$USE_HTTP01" -eq 1 ]; then
  # Port 80 must be free for standalone HTTP-01
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | awk '{print $4}' | grep -qE '(^|:)80$'; then
      color warn "Port 80 appears to be in use. HTTP-01 may fail. Stop any service on :80 or use --alpn."
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tln | awk '{print $4}' | grep -qE '(^|:)80$'; then
      color warn "Port 80 appears to be in use. HTTP-01 may fail. Stop any service on :80 or use --alpn."
    fi
  fi
else
  # ALPN requires 443
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | awk '{print $4}' | grep -qE '(^|:)443$'; then
      color warn "Port 443 appears to be in use. TLS-ALPN-01 may fail. Stop any service on :443 or use --http-01."
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tln | awk '{print $4}' | grep -qE '(^|:)443$'; then
      color warn "Port 443 appears to be in use. TLS-ALPN-01 may fail. Stop any service on :443 or use --http-01."
    fi
  fi
fi

RUN_COMMON_ARGS="--rm --network host -v ${STATE_DIR}:/acme.sh -v ${HOST_CA_BUNDLE}:${CONTAINER_CA}:ro -e SSL_CERT_FILE=${CONTAINER_CA} -e LE_WORKING_DIR=/acme.sh"
[ "$VERBOSE" -eq 1 ] && RUN_COMMON_ARGS="$RUN_COMMON_ARGS -e DEBUG=2"

# Run with selected client
if [ "$CLIENT" = "acme.sh" ]; then
  color info "Registering ACME account (acme.sh)"
  set -x
  docker run $RUN_COMMON_ARGS neilpang/acme.sh:latest \
    --register-account -m "$EMAIL" --server "$ACME_DIR"
  set +x

  if [ "$USE_ALPN" -eq 1 ]; then
    color info "Attempting issuance for $DOMAIN via TLS-ALPN-01 (acme.sh)"
    set -x
    docker run $RUN_COMMON_ARGS neilpang/acme.sh:latest \
      --issue -d "$DOMAIN" --alpn --server "$ACME_DIR"
    set +x
  else
    color info "Attempting issuance for $DOMAIN via HTTP-01 on port 80 (acme.sh)"
    set -x
    docker run $RUN_COMMON_ARGS neilpang/acme.sh:latest \
      --issue -d "$DOMAIN" --standalone --server "$ACME_DIR"
    set +x
  fi

  if [ -n "$DEPLOY_TO" ]; then
    color info "Deploying certs into Docker container '$DEPLOY_TO' via acme.sh deploy hook"
    set -x
    docker run $RUN_COMMON_ARGS neilpang/acme.sh:latest \
      --deploy -d "$DOMAIN" --deploy-hook docker --deploy-docker-container "$DEPLOY_TO"
    set +x
  fi

  color ok "acme.sh commands completed. Check ${STATE_DIR} for issued certs."

elif [ "$CLIENT" = "lego" ]; then
  color info "Using lego client (goacme/lego)"
  # Map state to /work for lego
  LEGO_COMMON_ARGS="--rm --network host -v ${STATE_DIR}:/work -v ${HOST_CA_BUNDLE}:${CONTAINER_CA}:ro -e SSL_CERT_FILE=${CONTAINER_CA}"
  [ "$VERBOSE" -eq 1 ] && LEGO_COMMON_ARGS="$LEGO_COMMON_ARGS -e LEGO_LOG_LEVEL=debug"

  CHALLENGE_FLAG="--tls"
  if [ "$USE_HTTP01" -eq 1 ]; then CHALLENGE_FLAG="--http"; fi

  color info "Register+Issue for $DOMAIN via lego ($CHALLENGE_FLAG)"
  set -x
  docker run $LEGO_COMMON_ARGS goacme/lego:latest \
    --path /work --server "$ACME_DIR" --email "$EMAIL" --accept-tos \
    $CHALLENGE_FLAG -d "$DOMAIN" run
  set +x

  if [ -n "$DEPLOY_TO" ]; then
    color warn "lego does not provide a built-in docker deploy hook like acme.sh. Skipping deploy."
  fi

  color ok "lego command completed. Check ${STATE_DIR} for issued certs."
else
  color err "Unknown client: $CLIENT (expected acme.sh or lego)"; exit 5
fi
