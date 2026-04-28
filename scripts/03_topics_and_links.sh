#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
load_lab_env
load_secrets

require_cmd confluent
require_var EAST_CLUSTER_ID
require_var WEST_CLUSTER_ID
require_var EAST_BOOTSTRAP
require_var WEST_BOOTSTRAP
require_var EAST_API_KEY
require_var EAST_API_SECRET
require_var WEST_API_KEY
require_var WEST_API_SECRET

CONFIG_DIR="$GENERATED_DIR/link-configs"
mkdir -p "$CONFIG_DIR"

cat >"$CONFIG_DIR/active-passive-west.config" <<'EOF'
link.mode=BIDIRECTIONAL
consumer.offset.sync.enable=true
consumer.offset.group.filters={"groupFilters": [{"name": "*", "patternType": "LITERAL", "filterType": "INCLUDE", "topicTypes": ["LOCAL_MIRROR"]}]}
consumer.offset.sync.ms=5000
EOF

cat >"$CONFIG_DIR/active-active-east.config" <<'EOF'
link.mode=BIDIRECTIONAL
cluster.link.prefix=west.
consumer.offset.sync.enable=true
consumer.offset.group.filters={"groupFilters": [{"name": "cg-east", "patternType": "LITERAL", "filterType": "INCLUDE", "topicTypes": ["REMOTE_MIRROR"]}, {"name": "cg-west", "patternType": "LITERAL", "filterType": "INCLUDE", "topicTypes": ["LOCAL_MIRROR"]}]}
consumer.offset.sync.ms=5000
EOF

cat >"$CONFIG_DIR/active-active-west.config" <<'EOF'
link.mode=BIDIRECTIONAL
cluster.link.prefix=east.
consumer.offset.sync.enable=true
consumer.offset.group.filters={"groupFilters": [{"name": "cg-west", "patternType": "LITERAL", "filterType": "INCLUDE", "topicTypes": ["REMOTE_MIRROR"]}, {"name": "cg-east", "patternType": "LITERAL", "filterType": "INCLUDE", "topicTypes": ["LOCAL_MIRROR"]}]}
consumer.offset.sync.ms=5000
EOF

create_topic() {
  local cluster_id="$1"
  local topic="$2"
  confluent kafka topic create "$topic" --cluster "$cluster_id" --partitions 6 >/dev/null || true
}

create_topic "$EAST_CLUSTER_ID" ap.orders
create_topic "$EAST_CLUSTER_ID" aa.orders
create_topic "$WEST_CLUSTER_ID" aa.orders

confluent kafka link create gateway-lab-ap \
  --cluster "$WEST_CLUSTER_ID" \
  --remote-cluster "$EAST_CLUSTER_ID" \
  --remote-bootstrap-server "$EAST_BOOTSTRAP" \
  --remote-api-key "$EAST_API_KEY" \
  --remote-api-secret "$EAST_API_SECRET" \
  --config "$CONFIG_DIR/active-passive-west.config" >/dev/null || true

confluent kafka mirror create ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap >/dev/null || true

confluent kafka link create gateway-lab-aa \
  --cluster "$WEST_CLUSTER_ID" \
  --remote-cluster "$EAST_CLUSTER_ID" \
  --remote-bootstrap-server "$EAST_BOOTSTRAP" \
  --remote-api-key "$EAST_API_KEY" \
  --remote-api-secret "$EAST_API_SECRET" \
  --config "$CONFIG_DIR/active-active-west.config" >/dev/null || true

confluent kafka link create gateway-lab-aa \
  --cluster "$EAST_CLUSTER_ID" \
  --remote-cluster "$WEST_CLUSTER_ID" \
  --remote-bootstrap-server "$WEST_BOOTSTRAP" \
  --remote-api-key "$WEST_API_KEY" \
  --remote-api-secret "$WEST_API_SECRET" \
  --config "$CONFIG_DIR/active-active-east.config" >/dev/null || true

confluent kafka mirror create east.aa.orders --source-topic aa.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-aa >/dev/null || true
confluent kafka mirror create west.aa.orders --source-topic aa.orders --cluster "$EAST_CLUSTER_ID" --link gateway-lab-aa >/dev/null || true

echo "Topics, links, and mirrors requested."
