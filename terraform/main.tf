locals {
  east_cluster_name = "gateway-lab-east-${var.lab_tag}"
  west_cluster_name = "gateway-lab-west-${var.lab_tag}"

  cluster_operations = toset([
    "CLUSTER_ACTION",
    "DESCRIBE",
    "DESCRIBE_CONFIGS",
    "IDEMPOTENT_WRITE",
  ])

  topic_operations = toset([
    "ALTER",
    "ALTER_CONFIGS",
    "CREATE",
    "DELETE",
    "DESCRIBE",
    "DESCRIBE_CONFIGS",
    "READ",
    "WRITE",
  ])

  group_operations = toset([
    "DESCRIBE",
    "READ",
  ])
}

resource "confluent_kafka_cluster" "east" {
  display_name = local.east_cluster_name
  availability = var.availability
  cloud        = var.cloud
  region       = var.east_region

  dedicated {
    cku = var.dedicated_cku
  }

  environment {
    id = var.environment_id
  }
}

resource "confluent_kafka_cluster" "west" {
  display_name = local.west_cluster_name
  availability = var.availability
  cloud        = var.cloud
  region       = var.west_region

  dedicated {
    cku = var.dedicated_cku
  }

  environment {
    id = var.environment_id
  }
}

resource "confluent_service_account" "east_gateway" {
  display_name = "gateway-lab-east-${var.lab_tag}"
  description  = "Service account for the Confluent Gateway lab east cluster."
}

resource "confluent_service_account" "west_gateway" {
  display_name = "gateway-lab-west-${var.lab_tag}"
  description  = "Service account for the Confluent Gateway lab west cluster."
}

resource "confluent_role_binding" "east_gateway_admin" {
  principal   = "User:${confluent_service_account.east_gateway.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.east.rbac_crn
}

resource "confluent_role_binding" "west_gateway_admin" {
  principal   = "User:${confluent_service_account.west_gateway.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.west.rbac_crn
}

resource "confluent_api_key" "east_gateway" {
  display_name = "gateway-lab-east-${var.lab_tag}"
  description  = "Kafka API key for Gateway lab east cluster."

  owner {
    id          = confluent_service_account.east_gateway.id
    api_version = confluent_service_account.east_gateway.api_version
    kind        = confluent_service_account.east_gateway.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.east.id
    api_version = confluent_kafka_cluster.east.api_version
    kind        = confluent_kafka_cluster.east.kind

    environment {
      id = var.environment_id
    }
  }

  depends_on = [confluent_role_binding.east_gateway_admin]
}

resource "confluent_api_key" "west_gateway" {
  display_name = "gateway-lab-west-${var.lab_tag}"
  description  = "Kafka API key for Gateway lab west cluster."

  owner {
    id          = confluent_service_account.west_gateway.id
    api_version = confluent_service_account.west_gateway.api_version
    kind        = confluent_service_account.west_gateway.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.west.id
    api_version = confluent_kafka_cluster.west.api_version
    kind        = confluent_kafka_cluster.west.kind

    environment {
      id = var.environment_id
    }
  }

  depends_on = [confluent_role_binding.west_gateway_admin]
}

resource "confluent_kafka_acl" "east_cluster" {
  for_each = local.cluster_operations

  kafka_cluster {
    id = confluent_kafka_cluster.east.id
  }

  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.east_gateway.id}"
  host          = "*"
  operation     = each.value
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.east.rest_endpoint

  credentials {
    key    = confluent_api_key.east_gateway.id
    secret = confluent_api_key.east_gateway.secret
  }
}

resource "confluent_kafka_acl" "east_topic" {
  for_each = local.topic_operations

  kafka_cluster {
    id = confluent_kafka_cluster.east.id
  }

  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.east_gateway.id}"
  host          = "*"
  operation     = each.value
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.east.rest_endpoint

  credentials {
    key    = confluent_api_key.east_gateway.id
    secret = confluent_api_key.east_gateway.secret
  }
}

resource "confluent_kafka_acl" "east_group" {
  for_each = local.group_operations

  kafka_cluster {
    id = confluent_kafka_cluster.east.id
  }

  resource_type = "GROUP"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.east_gateway.id}"
  host          = "*"
  operation     = each.value
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.east.rest_endpoint

  credentials {
    key    = confluent_api_key.east_gateway.id
    secret = confluent_api_key.east_gateway.secret
  }
}

resource "confluent_kafka_acl" "west_cluster" {
  for_each = local.cluster_operations

  kafka_cluster {
    id = confluent_kafka_cluster.west.id
  }

  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.west_gateway.id}"
  host          = "*"
  operation     = each.value
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.west.rest_endpoint

  credentials {
    key    = confluent_api_key.west_gateway.id
    secret = confluent_api_key.west_gateway.secret
  }
}

resource "confluent_kafka_acl" "west_topic" {
  for_each = local.topic_operations

  kafka_cluster {
    id = confluent_kafka_cluster.west.id
  }

  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.west_gateway.id}"
  host          = "*"
  operation     = each.value
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.west.rest_endpoint

  credentials {
    key    = confluent_api_key.west_gateway.id
    secret = confluent_api_key.west_gateway.secret
  }
}

resource "confluent_kafka_acl" "west_group" {
  for_each = local.group_operations

  kafka_cluster {
    id = confluent_kafka_cluster.west.id
  }

  resource_type = "GROUP"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.west_gateway.id}"
  host          = "*"
  operation     = each.value
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.west.rest_endpoint

  credentials {
    key    = confluent_api_key.west_gateway.id
    secret = confluent_api_key.west_gateway.secret
  }
}

resource "confluent_kafka_topic" "east_ap_orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.east.id
  }

  topic_name       = "ap.orders"
  partitions_count = var.topic_partitions
  rest_endpoint    = confluent_kafka_cluster.east.rest_endpoint

  credentials {
    key    = confluent_api_key.east_gateway.id
    secret = confluent_api_key.east_gateway.secret
  }

  depends_on = [
    confluent_kafka_acl.east_topic,
  ]
}

resource "confluent_kafka_topic" "east_aa_orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.east.id
  }

  topic_name       = "aa.orders"
  partitions_count = var.topic_partitions
  rest_endpoint    = confluent_kafka_cluster.east.rest_endpoint

  credentials {
    key    = confluent_api_key.east_gateway.id
    secret = confluent_api_key.east_gateway.secret
  }

  depends_on = [
    confluent_kafka_acl.east_topic,
  ]
}

resource "confluent_kafka_topic" "west_aa_orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.west.id
  }

  topic_name       = "aa.orders"
  partitions_count = var.topic_partitions
  rest_endpoint    = confluent_kafka_cluster.west.rest_endpoint

  credentials {
    key    = confluent_api_key.west_gateway.id
    secret = confluent_api_key.west_gateway.secret
  }

  depends_on = [
    confluent_kafka_acl.west_topic,
  ]
}

resource "confluent_cluster_link" "active_passive" {
  link_name = "gateway-lab-ap"
  link_mode = "DESTINATION"

  source_kafka_cluster {
    id                 = confluent_kafka_cluster.east.id
    bootstrap_endpoint = confluent_kafka_cluster.east.bootstrap_endpoint

    credentials {
      key    = confluent_api_key.east_gateway.id
      secret = confluent_api_key.east_gateway.secret
    }
  }

  destination_kafka_cluster {
    id            = confluent_kafka_cluster.west.id
    rest_endpoint = confluent_kafka_cluster.west.rest_endpoint

    credentials {
      key    = confluent_api_key.west_gateway.id
      secret = confluent_api_key.west_gateway.secret
    }
  }

  config = {
    "consumer.offset.sync.enable"   = "true"
    "consumer.offset.sync.ms"       = "5000"
    "consumer.offset.group.filters" = jsonencode({ groupFilters = [{ name = "*", patternType = "LITERAL", filterType = "INCLUDE", topicTypes = ["LOCAL_MIRROR"] }] })
  }

  depends_on = [
    confluent_kafka_topic.east_ap_orders,
    confluent_kafka_acl.east_cluster,
    confluent_kafka_acl.west_cluster,
  ]
}

resource "confluent_kafka_mirror_topic" "ap_orders" {
  source_kafka_topic {
    topic_name = confluent_kafka_topic.east_ap_orders.topic_name
  }

  cluster_link {
    link_name = confluent_cluster_link.active_passive.link_name
  }

  kafka_cluster {
    id            = confluent_kafka_cluster.west.id
    rest_endpoint = confluent_kafka_cluster.west.rest_endpoint

    credentials {
      key    = confluent_api_key.west_gateway.id
      secret = confluent_api_key.west_gateway.secret
    }
  }
}

resource "confluent_cluster_link" "active_active_west" {
  link_name = "gateway-lab-aa"
  link_mode = "BIDIRECTIONAL"

  local_kafka_cluster {
    id            = confluent_kafka_cluster.west.id
    rest_endpoint = confluent_kafka_cluster.west.rest_endpoint

    credentials {
      key    = confluent_api_key.west_gateway.id
      secret = confluent_api_key.west_gateway.secret
    }
  }

  remote_kafka_cluster {
    id                 = confluent_kafka_cluster.east.id
    bootstrap_endpoint = confluent_kafka_cluster.east.bootstrap_endpoint

    credentials {
      key    = confluent_api_key.east_gateway.id
      secret = confluent_api_key.east_gateway.secret
    }
  }

  config = {
    "cluster.link.prefix"           = "east."
    "consumer.offset.sync.enable"   = "true"
    "consumer.offset.sync.ms"       = "5000"
    "consumer.offset.group.filters" = jsonencode({ groupFilters = [{ name = "cg-west", patternType = "LITERAL", filterType = "INCLUDE", topicTypes = ["REMOTE_MIRROR"] }, { name = "cg-east", patternType = "LITERAL", filterType = "INCLUDE", topicTypes = ["LOCAL_MIRROR"] }] })
  }

  depends_on = [
    confluent_kafka_topic.east_aa_orders,
    confluent_kafka_topic.west_aa_orders,
  ]
}

resource "confluent_cluster_link" "active_active_east" {
  link_name = "gateway-lab-aa"
  link_mode = "BIDIRECTIONAL"

  local_kafka_cluster {
    id            = confluent_kafka_cluster.east.id
    rest_endpoint = confluent_kafka_cluster.east.rest_endpoint

    credentials {
      key    = confluent_api_key.east_gateway.id
      secret = confluent_api_key.east_gateway.secret
    }
  }

  remote_kafka_cluster {
    id                 = confluent_kafka_cluster.west.id
    bootstrap_endpoint = confluent_kafka_cluster.west.bootstrap_endpoint

    credentials {
      key    = confluent_api_key.west_gateway.id
      secret = confluent_api_key.west_gateway.secret
    }
  }

  config = {
    "cluster.link.prefix"           = "west."
    "consumer.offset.sync.enable"   = "true"
    "consumer.offset.sync.ms"       = "5000"
    "consumer.offset.group.filters" = jsonencode({ groupFilters = [{ name = "cg-east", patternType = "LITERAL", filterType = "INCLUDE", topicTypes = ["REMOTE_MIRROR"] }, { name = "cg-west", patternType = "LITERAL", filterType = "INCLUDE", topicTypes = ["LOCAL_MIRROR"] }] })
  }

  depends_on = [
    confluent_kafka_topic.east_aa_orders,
    confluent_kafka_topic.west_aa_orders,
  ]
}

resource "confluent_kafka_mirror_topic" "east_aa_orders" {
  source_kafka_topic {
    topic_name = confluent_kafka_topic.east_aa_orders.topic_name
  }

  mirror_topic_name = "east.aa.orders"

  cluster_link {
    link_name = confluent_cluster_link.active_active_west.link_name
  }

  kafka_cluster {
    id            = confluent_kafka_cluster.west.id
    rest_endpoint = confluent_kafka_cluster.west.rest_endpoint

    credentials {
      key    = confluent_api_key.west_gateway.id
      secret = confluent_api_key.west_gateway.secret
    }
  }
}

resource "confluent_kafka_mirror_topic" "west_aa_orders" {
  source_kafka_topic {
    topic_name = confluent_kafka_topic.west_aa_orders.topic_name
  }

  mirror_topic_name = "west.aa.orders"

  cluster_link {
    link_name = confluent_cluster_link.active_active_east.link_name
  }

  kafka_cluster {
    id            = confluent_kafka_cluster.east.id
    rest_endpoint = confluent_kafka_cluster.east.rest_endpoint

    credentials {
      key    = confluent_api_key.east_gateway.id
      secret = confluent_api_key.east_gateway.secret
    }
  }
}
