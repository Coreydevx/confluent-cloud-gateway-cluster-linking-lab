#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

target="${1:-}"
if [[ "$target" != "east" && "$target" != "west" ]]; then
  echo "Usage: $0 east|west" >&2
  exit 1
fi

"$LAB_DIR/scripts/04_render_gateway.sh" "$target"
docker compose -f "$GATEWAY_DIR/docker-compose.yaml" --project-directory "$GATEWAY_DIR" up -d --force-recreate
echo "Switchover route now points to $target."
