variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API key. Prefer TF_VAR_confluent_cloud_api_key instead of terraform.tfvars."
  type        = string
  sensitive   = true
  default     = null
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API secret. Prefer TF_VAR_confluent_cloud_api_secret instead of terraform.tfvars."
  type        = string
  sensitive   = true
  default     = null
}

variable "environment_id" {
  description = "Existing Confluent Cloud environment ID, for example env-abc123."
  type        = string
}

variable "lab_tag" {
  description = "Short tag used in resource names."
  type        = string
  default     = "tf"
}

variable "cloud" {
  description = "Cloud provider for the lab clusters."
  type        = string
  default     = "AWS"

  validation {
    condition     = contains(["AWS", "AZURE", "GCP"], var.cloud)
    error_message = "cloud must be AWS, AZURE, or GCP."
  }
}

variable "east_region" {
  description = "Region for the east lab cluster."
  type        = string
  default     = "us-east-1"
}

variable "west_region" {
  description = "Region for the west lab cluster."
  type        = string
  default     = "us-west-2"
}

variable "availability" {
  description = "Availability setting for the lab clusters."
  type        = string
  default     = "SINGLE_ZONE"

  validation {
    condition     = contains(["SINGLE_ZONE", "MULTI_ZONE"], var.availability)
    error_message = "availability must be SINGLE_ZONE or MULTI_ZONE for this lab."
  }
}

variable "dedicated_cku" {
  description = "CKUs per Dedicated cluster. SINGLE_ZONE requires at least 1. MULTI_ZONE requires at least 2."
  type        = number
  default     = 1
}

variable "topic_partitions" {
  description = "Partition count for lab topics."
  type        = number
  default     = 6
}

variable "gateway_client_user" {
  description = "Username clients use when connecting to the local Gateway."
  type        = string
  default     = "labclient"
}

variable "gateway_client_password" {
  description = "Password clients use when connecting to the local Gateway."
  type        = string
  sensitive   = true
  default     = "lab-password"
}

