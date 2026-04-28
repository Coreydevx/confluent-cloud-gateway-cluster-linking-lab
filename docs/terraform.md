# Terraform Setup

This is the infrastructure-as-code path for the lab. It creates the Confluent Cloud pieces, then exports the local `.lab.env` and `.secrets/gateway.env` files used by the Gateway scripts.

Use this path if you want repeatable cloud infrastructure. Use the Bash script path in the main README if you want the most direct learning experience.

## What Terraform Creates

Terraform creates:

- two Dedicated Kafka clusters
- one service account per cluster
- one Kafka API key per service account
- role bindings and ACLs for lab operations
- `ap.orders` on east
- `aa.orders` on east and west
- active/passive Cluster Link `gateway-lab-ap`
- mirror topic `ap.orders` on west
- bidirectional active/active Cluster Link `gateway-lab-aa`
- mirror topics `east.aa.orders` on west and `west.aa.orders` on east

Terraform does not start the local Gateway container. After Terraform finishes, you still run the Gateway scripts from the repo root.

## Compatibility

Terraform support is tested with the Confluent Terraform provider and Confluent Cloud to Confluent Cloud links. The provider documentation says Terraform can manage Cluster Links between two Confluent Cloud clusters; it cannot manage links to or from external Kafka or Confluent Platform clusters.

Useful references:

- Confluent Terraform provider: https://registry.terraform.io/providers/confluentinc/confluent/latest
- `confluent_cluster_link` resource: https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_cluster_link
- `confluent_kafka_mirror_topic` resource: https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_mirror_topic
- Cluster Linking docs: https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/index.html

## Security Warning

Terraform state can contain sensitive values, including Confluent Cloud API secrets and Kafka API secrets. Treat `terraform.tfstate` like a secret.

For a real team:

- use a remote encrypted backend
- restrict access to the state backend
- do not commit `terraform.tfstate`, `terraform.tfvars`, or `.terraform/`
- prefer environment variables for Cloud API credentials

This repo intentionally ignores Terraform state files.

## Step 1: Create A Cloud API Key

Create or choose a Confluent Cloud API key that can create clusters, service accounts, API keys, role bindings, ACLs, topics, Cluster Links, and mirror topics.

Set it in your shell:

```bash
export TF_VAR_confluent_cloud_api_key="YOUR_CLOUD_API_KEY"
export TF_VAR_confluent_cloud_api_secret="YOUR_CLOUD_API_SECRET"
```

## Step 2: Choose A Confluent Environment

List your environments:

```bash
confluent environment list
```

Copy the environment ID you want to use. It looks like `env-abc123`.

## Step 3: Configure Terraform Variables

From the repo root:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and change:

```hcl
environment_id = "env-abc123"
```

Optional values:

- `lab_tag`: short suffix for resource names
- `east_region`: default `us-east-1`
- `west_region`: default `us-west-2`
- `dedicated_cku`: default `1`

## Step 4: Initialize Terraform

```bash
terraform init
```

This downloads the Confluent Terraform provider.

## Step 5: Review The Plan

```bash
terraform plan -out tfplan
```

Read the plan before applying. The plan should show two Dedicated clusters and the supporting lab resources.

## Step 6: Apply

```bash
terraform apply tfplan
```

Dedicated clusters take time to provision. If the apply waits for a while, that is normal.

## Step 7: Export Files For Gateway

Return to the repo root and export Terraform outputs into the files used by the Gateway scripts:

```bash
cd ..
./scripts/export_terraform_outputs.sh
```

This writes:

- `.lab.env`
- `.secrets/gateway.env`

Both files are ignored by git.

## Step 8: Start Gateway

```bash
./scripts/04_render_gateway.sh east
./scripts/05_start_gateway.sh
```

Run a probe:

```bash
./scripts/install_python_deps.sh
. .venv/bin/activate
python workloads/gateway_probe.py --topic ap.orders --group cg-ap --seconds 60 --rate 10
```

## Step 9: Try Failover

Load the exported environment file:

```bash
. .lab.env
```

Check west mirror lag:

```bash
confluent kafka mirror describe ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
```

When lag is `0`, fail over:

```bash
confluent kafka mirror failover ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
./scripts/06_switch_route.sh west
```

Run the probe again:

```bash
python workloads/gateway_probe.py --topic ap.orders --group cg-ap --seconds 60 --rate 10
```

## Step 10: Clean Up

Stop local containers first:

```bash
make clean-local
```

Then destroy Terraform-managed cloud resources:

```bash
cd terraform
terraform destroy
```

Read the destroy plan carefully. Type `yes` only when you are ready to delete the billable lab resources.

## Troubleshooting

If `terraform apply` fails while creating Cluster Links or mirror topics, wait a minute and run `terraform apply` again. Newly created role bindings and ACLs can take a short time to become effective.

If a mirror topic was promoted or failed over during testing, Terraform may no longer be able to manage it as a mirror topic. In that case, remove the mirror topic from state or clean up the lab manually before destroying.

If you want to use existing clusters instead of Terraform-created clusters, use the Bash script path in the main README. This Terraform example intentionally keeps the first version simple by owning the two lab clusters it creates.
