# Compatibility Matrix

This lab is built around Bash, Docker, the Confluent CLI, Terraform, and Python.

## Operating Systems

| Platform | Status | Notes |
| --- | --- | --- |
| macOS | Tested | Developed and tested on macOS with Docker Desktop. |
| Linux | Supported | Expected to work with Docker Engine or Docker Desktop, Bash, `jq`, Python, Terraform, and Confluent CLI. |
| Windows with WSL2 | Supported | Run the commands inside a Linux WSL2 distro. Docker Desktop with WSL integration is recommended. |
| Native Windows PowerShell | Not supported | The scripts are Bash scripts. Use WSL2 or port the scripts to PowerShell. |

## Tool Versions

| Tool | Minimum | Notes |
| --- | --- | --- |
| Confluent CLI | v4 | Used for the script-based path and for mirror failover commands. |
| Docker Compose | v2 | Starts the local Gateway and Vault containers. |
| Python | 3.10 | Runs the workload probe. |
| Terraform | 1.6 | Required only for the optional Terraform path. |
| Confluent Terraform provider | 2.30 | Required only for the optional Terraform path. |
| `jq` | 1.6 | Used by the Bash provisioning scripts. |

## Cluster Support

| Cluster Type | Script Path | Terraform Path | Notes |
| --- | --- | --- | --- |
| Dedicated | Supported | Supported | Recommended for this lab. |
| Enterprise | Likely supported for existing clusters | Not covered by the provided Terraform | Validate Cluster Linking support in your environment before using. |
| Standard | Source only for some Cluster Linking cases | Not covered | Cluster Linking destinations must be supported cluster types. |
| Basic | Source only for some Cluster Linking cases | Not covered | Not recommended for this lab. |
| Freight | Not supported for Cluster Linking | Not supported | Cluster Linking on Freight is not supported. |

## Networking

The default lab assumes public Confluent Cloud endpoints and a local Gateway container. PrivateLink, VPC peering, Transit Gateway, Private Service Connect, and PNI can be added later, but are intentionally outside this beginner-friendly version.

