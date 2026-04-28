#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd confluent
require_cmd jq
require_var ENVIRONMENT_ID

mkdir -p "$GENERATED_DIR"

east_name="${EAST_CLUSTER_NAME:-gateway-lab-east-$LAB_TAG}"
west_name="${WEST_CLUSTER_NAME:-gateway-lab-west-$LAB_TAG}"

echo "Creating two $CLUSTER_TYPE clusters. Dedicated clusters incur Confluent Cloud charges while they exist."

east_json="$(confluent kafka cluster create "$east_name" \
  --type "$CLUSTER_TYPE" \
  --cloud "$CLOUD_PROVIDER" \
  --region "$EAST_REGION" \
  --cku "$CKU" \
  --availability "$AVAILABILITY" \
  --environment "$ENVIRONMENT_ID" \
  -o json)"

west_json="$(confluent kafka cluster create "$west_name" \
  --type "$CLUSTER_TYPE" \
  --cloud "$CLOUD_PROVIDER" \
  --region "$WEST_REGION" \
  --cku "$CKU" \
  --availability "$AVAILABILITY" \
  --environment "$ENVIRONMENT_ID" \
  -o json)"

cat >"$ENV_FILE" <<EOF
export ENVIRONMENT_ID="$ENVIRONMENT_ID"
export LAB_TAG="$LAB_TAG"
export EAST_CLUSTER_ID="$(jq -r '.id' <<<"$east_json")"
export WEST_CLUSTER_ID="$(jq -r '.id' <<<"$west_json")"
export GATEWAY_CLIENT_USER="${GATEWAY_CLIENT_USER:-labclient}"
export GATEWAY_CLIENT_PASSWORD="${GATEWAY_CLIENT_PASSWORD:-lab-password}"
EOF

echo "Wrote $ENV_FILE"
echo "Run ./scripts/01_wait_for_clusters.sh next."
