#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd terraform

TF_DIR="$LAB_DIR/terraform"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

terraform -chdir="$TF_DIR" output -raw lab_env >"$ENV_FILE"
terraform -chdir="$TF_DIR" output -raw gateway_secrets_env >"$SECRETS_FILE"

chmod 600 "$ENV_FILE" "$SECRETS_FILE"

echo "Wrote $ENV_FILE"
echo "Wrote $SECRETS_FILE"
echo "You can now run ./scripts/04_render_gateway.sh east"

