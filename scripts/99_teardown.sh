#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "This deletes the local Gateway containers and the two lab Dedicated clusters."
read -r -p "Type DELETE to continue: " confirmation
if [[ "$confirmation" != "DELETE" ]]; then
  echo "Aborted."
  exit 1
fi

if [[ -f "$GATEWAY_DIR/docker-compose.yaml" ]]; then
  docker compose -f "$GATEWAY_DIR/docker-compose.yaml" --project-directory "$GATEWAY_DIR" down -v || true
fi

confluent kafka cluster delete "$EAST_CLUSTER_ID" --force || true
confluent kafka cluster delete "$WEST_CLUSTER_ID" --force || true
echo "Teardown requested."

