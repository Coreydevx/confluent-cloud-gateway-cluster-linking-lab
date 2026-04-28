#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
load_lab_env

require_cmd confluent
require_cmd jq
require_var EAST_CLUSTER_ID
require_var WEST_CLUSTER_ID

mkdir -p "$GENERATED_DIR"

echo "Waiting for clusters to be UP..."
while true; do
  east_json="$(confluent kafka cluster describe "$EAST_CLUSTER_ID" -o json)"
  west_json="$(confluent kafka cluster describe "$WEST_CLUSTER_ID" -o json)"

  east_status="$(jq -r '.status' <<<"$east_json")"
  west_status="$(jq -r '.status' <<<"$west_json")"
  east_endpoint="$(jq -r '.endpoint' <<<"$east_json")"
  west_endpoint="$(jq -r '.endpoint' <<<"$west_json")"

  printf "east=%s west=%s\n" "$east_status" "$west_status"

  if [[ "$east_status" == "UP" && "$west_status" == "UP" && -n "$east_endpoint" && -n "$west_endpoint" ]]; then
    cat >"$ENV_FILE" <<EOF
export ENVIRONMENT_ID="${ENVIRONMENT_ID:-}"
export LAB_TAG="$LAB_TAG"
export EAST_CLUSTER_ID="$EAST_CLUSTER_ID"
export WEST_CLUSTER_ID="$WEST_CLUSTER_ID"
export EAST_BOOTSTRAP="$east_endpoint"
export WEST_BOOTSTRAP="$west_endpoint"
export EAST_BOOTSTRAP_HOSTPORT="$(endpoint_hostport "$east_endpoint")"
export WEST_BOOTSTRAP_HOSTPORT="$(endpoint_hostport "$west_endpoint")"
export GATEWAY_CLIENT_USER="${GATEWAY_CLIENT_USER:-labclient}"
export GATEWAY_CLIENT_PASSWORD="${GATEWAY_CLIENT_PASSWORD:-lab-password}"
EOF
    echo "Wrote $ENV_FILE"
    break
  fi

  sleep 60
done
