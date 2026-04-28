#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ ! -f "$GATEWAY_DIR/docker-compose.yaml" ]]; then
  echo "Run ./scripts/04_render_gateway.sh east first." >&2
  exit 1
fi

docker compose -f "$GATEWAY_DIR/docker-compose.yaml" --project-directory "$GATEWAY_DIR" up -d
docker compose -f "$GATEWAY_DIR/docker-compose.yaml" --project-directory "$GATEWAY_DIR" ps

