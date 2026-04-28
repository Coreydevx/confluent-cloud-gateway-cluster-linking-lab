output "east_cluster_id" {
  description = "East Kafka cluster ID."
  value       = confluent_kafka_cluster.east.id
}

output "west_cluster_id" {
  description = "West Kafka cluster ID."
  value       = confluent_kafka_cluster.west.id
}

output "east_bootstrap" {
  description = "East Kafka bootstrap endpoint."
  value       = confluent_kafka_cluster.east.bootstrap_endpoint
}

output "west_bootstrap" {
  description = "West Kafka bootstrap endpoint."
  value       = confluent_kafka_cluster.west.bootstrap_endpoint
}

output "lab_env" {
  description = "Contents to write to ../.lab.env for the Gateway scripts."
  value       = <<EOT
export ENVIRONMENT_ID="${var.environment_id}"
export LAB_TAG="${var.lab_tag}"
export EAST_CLUSTER_ID="${confluent_kafka_cluster.east.id}"
export WEST_CLUSTER_ID="${confluent_kafka_cluster.west.id}"
export EAST_BOOTSTRAP="${confluent_kafka_cluster.east.bootstrap_endpoint}"
export WEST_BOOTSTRAP="${confluent_kafka_cluster.west.bootstrap_endpoint}"
export EAST_BOOTSTRAP_HOSTPORT="${trimprefix(confluent_kafka_cluster.east.bootstrap_endpoint, "SASL_SSL://")}"
export WEST_BOOTSTRAP_HOSTPORT="${trimprefix(confluent_kafka_cluster.west.bootstrap_endpoint, "SASL_SSL://")}"
export GATEWAY_CLIENT_USER="${var.gateway_client_user}"
export GATEWAY_CLIENT_PASSWORD="${var.gateway_client_password}"
EOT
  sensitive   = true
}

output "gateway_secrets_env" {
  description = "Contents to write to ../.secrets/gateway.env for Gateway auth swapping."
  value       = <<EOT
export EAST_SERVICE_ACCOUNT="${confluent_service_account.east_gateway.id}"
export WEST_SERVICE_ACCOUNT="${confluent_service_account.west_gateway.id}"
export EAST_API_KEY="${confluent_api_key.east_gateway.id}"
export EAST_API_SECRET="${confluent_api_key.east_gateway.secret}"
export WEST_API_KEY="${confluent_api_key.west_gateway.id}"
export WEST_API_SECRET="${confluent_api_key.west_gateway.secret}"
EOT
  sensitive   = true
}

