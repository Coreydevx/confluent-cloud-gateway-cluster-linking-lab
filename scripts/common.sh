#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$LAB_DIR/.lab.env"
SECRETS_DIR="$LAB_DIR/.secrets"
SECRETS_FILE="$SECRETS_DIR/gateway.env"
GENERATED_DIR="$LAB_DIR/.generated"
GATEWAY_DIR="$GENERATED_DIR/gateway"

EAST_CLUSTER_ID="${EAST_CLUSTER_ID:-}"
WEST_CLUSTER_ID="${WEST_CLUSTER_ID:-}"
ENVIRONMENT_ID="${ENVIRONMENT_ID:-}"
LAB_TAG="${LAB_TAG:-$(date +%Y%m%d%H%M%S)}"
GATEWAY_IMAGE="${GATEWAY_IMAGE:-confluentinc/confluent-gateway-for-cloud:1.1.0}"
EAST_REGION="${EAST_REGION:-us-east-1}"
WEST_REGION="${WEST_REGION:-us-west-2}"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-aws}"
CLUSTER_TYPE="${CLUSTER_TYPE:-dedicated}"
CKU="${CKU:-1}"
AVAILABILITY="${AVAILABILITY:-single-zone}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    echo "Set it in your shell or run the earlier setup scripts to generate .lab.env." >&2
    exit 1
  fi
}

load_lab_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
}

load_secrets() {
  if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
  fi
}

endpoint_hostport() {
  local endpoint="$1"
  endpoint="${endpoint#SASL_SSL://}"
  endpoint="${endpoint#SSL://}"
  echo "$endpoint"
}
