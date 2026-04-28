#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
load_lab_env

require_cmd confluent
require_cmd jq
require_var ENVIRONMENT_ID
require_var EAST_CLUSTER_ID
require_var WEST_CLUSTER_ID

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [[ -f "$SECRETS_FILE" && "${FORCE:-0}" != "1" ]]; then
  echo "$SECRETS_FILE already exists. Set FORCE=1 to create fresh API keys."
  exit 0
fi

create_sa() {
  local name="$1"
  local existing
  existing="$(confluent iam service-account list -o json | jq -r --arg name "$name" '.[] | select(.name == $name) | .id' | head -n1)"
  if [[ -n "$existing" ]]; then
    echo "$existing"
  else
    confluent iam service-account create "$name" --description "Gateway lab service account" -o json | jq -r '.id'
  fi
}

create_key() {
  local cluster_id="$1"
  local sa_id="$2"
  confluent api-key create --resource "$cluster_id" --service-account "$sa_id" -o json
}

grant_admin() {
  local cluster_id="$1"
  local sa_id="$2"
  confluent iam rbac role-binding create \
    --principal "User:$sa_id" \
    --role CloudClusterAdmin \
    --environment "$ENVIRONMENT_ID" \
    --cloud-cluster "$cluster_id" >/dev/null || true
}

grant_acls() {
  local cluster_id="$1"
  local sa_id="$2"
  confluent kafka acl create --cluster "$cluster_id" --allow --service-account "$sa_id" \
    --operations describe,describe-configs,cluster-action,idempotent-write --cluster-scope >/dev/null || true
  confluent kafka acl create --cluster "$cluster_id" --allow --service-account "$sa_id" \
    --operations read,write,create,delete,alter,alter-configs,describe,describe-configs --topic "*" >/dev/null || true
  confluent kafka acl create --cluster "$cluster_id" --allow --service-account "$sa_id" \
    --operations read,describe --consumer-group "*" >/dev/null || true
}

east_sa="$(create_sa "gateway-lab-east-$LAB_TAG")"
west_sa="$(create_sa "gateway-lab-west-$LAB_TAG")"

grant_admin "$EAST_CLUSTER_ID" "$east_sa"
grant_admin "$WEST_CLUSTER_ID" "$west_sa"
grant_acls "$EAST_CLUSTER_ID" "$east_sa"
grant_acls "$WEST_CLUSTER_ID" "$west_sa"

east_key_json="$(create_key "$EAST_CLUSTER_ID" "$east_sa")"
west_key_json="$(create_key "$WEST_CLUSTER_ID" "$west_sa")"

cat >"$SECRETS_FILE" <<EOF
export EAST_SERVICE_ACCOUNT="$east_sa"
export WEST_SERVICE_ACCOUNT="$west_sa"
export EAST_API_KEY="$(jq -r '.key // .api_key // .id' <<<"$east_key_json")"
export EAST_API_SECRET="$(jq -r '.secret // .api_secret' <<<"$east_key_json")"
export WEST_API_KEY="$(jq -r '.key // .api_key // .id' <<<"$west_key_json")"
export WEST_API_SECRET="$(jq -r '.secret // .api_secret' <<<"$west_key_json")"
EOF
chmod 600 "$SECRETS_FILE"

if grep -q '"null"' "$SECRETS_FILE"; then
  echo "API key creation returned an unexpected shape. Inspect Confluent CLI output before continuing." >&2
  exit 1
fi
echo "Wrote $SECRETS_FILE"
