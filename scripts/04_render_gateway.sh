#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
load_lab_env
load_secrets

require_var EAST_BOOTSTRAP_HOSTPORT
require_var WEST_BOOTSTRAP_HOSTPORT
require_var EAST_API_KEY
require_var EAST_API_SECRET
require_var WEST_API_KEY
require_var WEST_API_SECRET

active="${1:-east}"
case "$active" in
  east)
    active_domain="east-cloud"
    active_store="active-store"
    active_key="$EAST_API_KEY"
    active_secret="$EAST_API_SECRET"
    ;;
  west)
    active_domain="west-cloud"
    active_store="active-store"
    active_key="$WEST_API_KEY"
    active_secret="$WEST_API_SECRET"
    ;;
  *)
    echo "Usage: $0 east|west" >&2
    exit 1
    ;;
esac

mkdir -p "$GATEWAY_DIR/config"

cat >"$GATEWAY_DIR/config/jaas-gateway-client.conf" <<EOF
org.apache.kafka.common.security.plain.PlainLoginModule required user_${GATEWAY_CLIENT_USER}="${GATEWAY_CLIENT_PASSWORD}";
EOF

cat >"$GATEWAY_DIR/config/jaas-cluster-template.conf" <<'EOF'
org.apache.kafka.common.security.plain.PlainLoginModule required username="%s" password="%s";
EOF

cat >"$GATEWAY_DIR/client.properties" <<EOF
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${GATEWAY_CLIENT_USER}" password="${GATEWAY_CLIENT_PASSWORD}";
EOF

cat >"$GATEWAY_DIR/.env" <<EOF
EAST_API_KEY=$EAST_API_KEY
EAST_API_SECRET=$EAST_API_SECRET
WEST_API_KEY=$WEST_API_KEY
WEST_API_SECRET=$WEST_API_SECRET
ACTIVE_API_KEY=$active_key
ACTIVE_API_SECRET=$active_secret
GATEWAY_CLIENT_USER=$GATEWAY_CLIENT_USER
GATEWAY_IMAGE=$GATEWAY_IMAGE
EOF
chmod 600 "$GATEWAY_DIR/.env"

cat >"$GATEWAY_DIR/gateway.yaml" <<EOF
gateway:
  name: cloud-gateway-cluster-linking-lab
  admin:
    bindAddress: 0.0.0.0
    port: 9190
    endpoints:
      metrics: true
  secretStores:
    - name: active-store
      provider:
        type: Vault
        config:
          address: http://vault:8200
          authToken: vault-plaintext-root-token
          path: secret/gateway/active
          separator: /
    - name: east-store
      provider:
        type: Vault
        config:
          address: http://vault:8200
          authToken: vault-plaintext-root-token
          path: secret/gateway/east
          separator: /
    - name: west-store
      provider:
        type: Vault
        config:
          address: http://vault:8200
          authToken: vault-plaintext-root-token
          path: secret/gateway/west
          separator: /
  streamingDomains:
    - name: east-cloud
      type: kafka
      kafkaCluster:
        name: gateway-lab-east
        nodeIdRanges:
          - name: cc-brokers
            start: 0
            end: 11
        bootstrapServers:
          - id: east-bootstrap
            endpoint: "$EAST_BOOTSTRAP_HOSTPORT"
            ssl:
              truststore:
    - name: west-cloud
      type: kafka
      kafkaCluster:
        name: gateway-lab-west
        nodeIdRanges:
          - name: cc-brokers
            start: 0
            end: 11
        bootstrapServers:
          - id: west-bootstrap
            endpoint: "$WEST_BOOTSTRAP_HOSTPORT"
            ssl:
              truststore:
  routes:
    - name: switchover-route
      endpoint: "localhost:19092"
      brokerIdentificationStrategy:
        type: port
      streamingDomain:
        name: $active_domain
        bootstrapServerId: ${active_domain%-cloud}-bootstrap
      security:
        auth: swap
        swapConfig:
          clientAuth:
            sasl:
              mechanism: PLAIN
              callbackHandlerClass: org.apache.kafka.common.security.plain.internals.PlainServerCallbackHandler
              jaasConfig:
                file: /etc/gateway/config/jaas-gateway-client.conf
          secretStore: $active_store
          clusterAuth:
            sasl:
              mechanism: PLAIN
              callbackHandlerClass: org.apache.kafka.common.security.authenticator.SaslClientCallbackHandler
              jaasConfig:
                file: /etc/gateway/config/jaas-cluster-template.conf
    - name: east-direct-route
      endpoint: "localhost:19192"
      brokerIdentificationStrategy:
        type: port
      streamingDomain:
        name: east-cloud
        bootstrapServerId: east-bootstrap
      security:
        auth: swap
        swapConfig:
          clientAuth:
            sasl:
              mechanism: PLAIN
              callbackHandlerClass: org.apache.kafka.common.security.plain.internals.PlainServerCallbackHandler
              jaasConfig:
                file: /etc/gateway/config/jaas-gateway-client.conf
          secretStore: east-store
          clusterAuth:
            sasl:
              mechanism: PLAIN
              callbackHandlerClass: org.apache.kafka.common.security.authenticator.SaslClientCallbackHandler
              jaasConfig:
                file: /etc/gateway/config/jaas-cluster-template.conf
    - name: west-direct-route
      endpoint: "localhost:19292"
      brokerIdentificationStrategy:
        type: port
      streamingDomain:
        name: west-cloud
        bootstrapServerId: west-bootstrap
      security:
        auth: swap
        swapConfig:
          clientAuth:
            sasl:
              mechanism: PLAIN
              callbackHandlerClass: org.apache.kafka.common.security.plain.internals.PlainServerCallbackHandler
              jaasConfig:
                file: /etc/gateway/config/jaas-gateway-client.conf
          secretStore: west-store
          clusterAuth:
            sasl:
              mechanism: PLAIN
              callbackHandlerClass: org.apache.kafka.common.security.authenticator.SaslClientCallbackHandler
              jaasConfig:
                file: /etc/gateway/config/jaas-cluster-template.conf
EOF

cat >"$GATEWAY_DIR/docker-compose.yaml" <<'EOF'
services:
  vault:
    image: hashicorp/vault:1.14
    hostname: vault
    container_name: gateway-lab-vault
    env_file:
      - .env
    ports:
      - "8200:8200"
    environment:
      VAULT_ADDR: "http://0.0.0.0:8200"
      VAULT_API_ADDR: "http://0.0.0.0:8200"
      VAULT_DEV_ROOT_TOKEN_ID: "vault-plaintext-root-token"
    command:
      - /bin/sh
      - -c
      - |
        /usr/local/bin/docker-entrypoint.sh server -dev &
        until vault status >/dev/null 2>&1; do sleep 1; done
        export VAULT_TOKEN="$${VAULT_DEV_ROOT_TOKEN_ID}"
        vault kv put secret/gateway/east "$${GATEWAY_CLIENT_USER}=$${EAST_API_KEY}/$${EAST_API_SECRET}"
        vault kv put secret/gateway/west "$${GATEWAY_CLIENT_USER}=$${WEST_API_KEY}/$${WEST_API_SECRET}"
        vault kv put secret/gateway/active "$${GATEWAY_CLIENT_USER}=$${ACTIVE_API_KEY}/$${ACTIVE_API_SECRET}"
        sleep infinity

  gateway:
    image: "${GATEWAY_IMAGE}"
    container_name: gateway-lab
    depends_on:
      - vault
    volumes:
      - ./gateway.yaml:/etc/gateway/gateway.yaml:ro
      - ./config:/etc/gateway/config:ro
    environment:
      GATEWAY_CONFIG_FILE: /etc/gateway/gateway.yaml
    ports:
      - "19092-19104:19092-19104"
      - "19192-19204:19192-19204"
      - "19292-19304:19292-19304"
      - "9190:9190"
    command: |
      bash -c "
        chmod +x /etc/confluent/docker/run 2>/dev/null || true
        exec /etc/confluent/docker/run
      "
EOF

echo "Rendered Gateway for active=$active in $GATEWAY_DIR"
