.PHONY: check create-clusters wait auth links gateway-east gateway-west deps probe clean-local terraform-check

check:
	bash -n scripts/*.sh
	python3 -m py_compile workloads/gateway_probe.py

terraform-check:
	terraform -chdir=terraform fmt -check
	terraform -chdir=terraform validate

create-clusters:
	./scripts/00_create_clusters.sh

wait:
	./scripts/01_wait_for_clusters.sh

auth:
	./scripts/02_provision_auth.sh

links:
	./scripts/03_topics_and_links.sh

gateway-east:
	./scripts/04_render_gateway.sh east
	./scripts/05_start_gateway.sh

gateway-west:
	./scripts/06_switch_route.sh west

deps:
	./scripts/install_python_deps.sh

probe:
	. .venv/bin/activate && python workloads/gateway_probe.py --topic ap.orders --group cg-ap --seconds 60 --rate 10

clean-local:
	if [ -f .generated/gateway/docker-compose.yaml ]; then docker compose -f .generated/gateway/docker-compose.yaml --project-directory .generated/gateway down -v; fi
