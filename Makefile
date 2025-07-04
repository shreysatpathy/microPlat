# Makefile for microPlat infrastructure testing and management

.PHONY: help install test test-fast test-helm test-k8s test-docker test-integration lint clean setup-dev deploy-monitoring test-monitoring

# Default target
help:
	@echo "Available targets:"
	@echo "  help           - Show this help message"
	@echo "  install        - Install test dependencies"
	@echo "  setup-dev      - Set up development environment"
	@echo "  test           - Run all tests"
	@echo "  test-fast      - Run fast tests only"
	@echo "  test-helm      - Run Helm chart tests"
	@echo "  test-k8s       - Run Kubernetes manifest tests"
	@echo "  test-docker    - Run Docker build tests"
	@echo "  test-integration - Run integration tests"
	@echo "  test-monitoring - Run monitoring stack tests"
	@echo "  deploy-monitoring - Deploy kube-prometheus-stack"
	@echo "  lint           - Run linting on all components"
	@echo "  clean          - Clean up test artifacts"
	@echo "  validate       - Validate all infrastructure components"

# Install test dependencies
install:
	@echo "Installing test dependencies..."
	pip install -r tests/requirements.txt

# Set up development environment
setup-dev: install
	@echo "Setting up development environment..."
	@if command -v helm >/dev/null 2>&1; then \
		echo "Helm is already installed"; \
	else \
		echo "Please install Helm: https://helm.sh/docs/intro/install/"; \
	fi
	@if command -v docker >/dev/null 2>&1; then \
		echo "Docker is already installed"; \
	else \
		echo "Please install Docker: https://docs.docker.com/get-docker/"; \
	fi
	@if command -v kubectl >/dev/null 2>&1; then \
		echo "kubectl is already installed"; \
	else \
		echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"; \
	fi

# Run all tests
test: install
	@echo "Running all tests..."
	pytest tests/ -v --tb=short --cov=. --cov-report=term-missing

# Run fast tests only (exclude slow integration tests)
test-fast: install
	@echo "Running fast tests..."
	pytest tests/ -v --tb=short -m "not slow"

# Run Helm chart tests
test-helm: install
	@echo "Running Helm chart tests..."
	pytest tests/test_helm_charts.py -v --tb=short

# Run Kubernetes manifest tests
test-k8s: install
	@echo "Running Kubernetes manifest tests..."
	pytest tests/test_kubernetes_manifests.py -v --tb=short

# Run Docker build tests
test-docker: install
	@echo "Running Docker build tests..."
	pytest tests/test_docker_builds.py -v --tb=short

# Run integration tests
test-integration: install
	@echo "Running integration tests..."
	pytest tests/test_integration.py -v --tb=short

# Lint all components
lint:
	@echo "Linting Helm charts..."
	@for chart in charts/*/; do \
		if [ -f "$$chart/Chart.yaml" ]; then \
			echo "Linting $$chart"; \
			helm lint "$$chart" || true; \
		fi \
	done
	@echo "Validating Kubernetes manifests..."
	@if command -v kubeval >/dev/null 2>&1; then \
		find manifests -name "*.yaml" -o -name "*.yml" | xargs kubeval || true; \
	else \
		echo "kubeval not installed, skipping manifest validation"; \
	fi
	@echo "Checking YAML syntax..."
	@find . -name "*.yaml" -o -name "*.yml" | grep -v ".git" | xargs -I {} python -c "import yaml; yaml.safe_load(open('{}'))" || true

# Validate all infrastructure components
validate: lint
	@echo "Validating Helm templates..."
	@for chart in charts/*/; do \
		if [ -f "$$chart/Chart.yaml" ]; then \
			echo "Templating $$chart"; \
			helm template test "$$chart" --debug --dry-run > /dev/null || true; \
		fi \
	done
	@echo "Checking for security issues..."
	@if command -v trivy >/dev/null 2>&1; then \
		trivy fs . --security-checks vuln,config || true; \
	else \
		echo "trivy not installed, skipping security scan"; \
	fi

# Clean up test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	rm -rf htmlcov/
	rm -rf .coverage
	rm -rf coverage.xml
	rm -rf .pytest_cache/
	rm -rf test-summary.md
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Development shortcuts
dev-test: test-fast
dev-lint: lint
dev-validate: validate

# CI/CD targets
ci-test: install test
ci-validate: install validate

# Docker-specific targets
docker-build-test:
	@echo "Testing Docker builds..."
	@for image in notebook trainer serve; do \
		if [ -f "docker/$$image/Dockerfile" ]; then \
			echo "Building test image for $$image"; \
			docker build --no-cache -t test-$$image:latest docker/$$image/ || echo "Build failed for $$image"; \
		fi \
	done

docker-clean:
	@echo "Cleaning up test Docker images..."
	@docker images | grep "^test-" | awk '{print $$3}' | xargs -r docker rmi || true

# Helm-specific targets
helm-dependency-update:
	@echo "Updating Helm dependencies..."
	@for chart in charts/*/; do \
		if [ -f "$$chart/Chart.yaml" ]; then \
			echo "Updating dependencies for $$chart"; \
			helm dependency update "$$chart" || true; \
		fi \
	done

# Monitoring stack targets
deploy-monitoring:
	@echo "Deploying kube-prometheus-stack monitoring..."
	@echo "Adding Prometheus community Helm repository..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	@echo "Creating monitoring namespace..."
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
	@echo "Installing kube-prometheus-stack..."
	helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		--values charts/kube-prometheus-stack/values.yaml \
		--wait --timeout=10m
	@echo "Monitoring stack deployed successfully!"
	@echo "Access Grafana: kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
	@echo "Access Prometheus: kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090"

test-monitoring: install
	@echo "Running monitoring stack tests..."
	pytest tests/test_monitoring.py -v --tb=short

monitoring-status:
	@echo "Checking monitoring stack status..."
	@echo "=== Monitoring Namespace ==="
	kubectl get all -n monitoring
	@echo "\n=== Prometheus Rules ==="
	kubectl get prometheusrule -n monitoring
	@echo "\n=== Service Monitors ==="
	kubectl get servicemonitor -n monitoring
	@echo "\n=== Persistent Volume Claims ==="
	kubectl get pvc -n monitoring

monitoring-clean:
	@echo "Cleaning up monitoring stack..."
	helm uninstall prometheus-stack -n monitoring || true
	kubectl delete namespace monitoring || true

monitoring-logs:
	@echo "Fetching monitoring component logs..."
	@echo "=== Prometheus Operator Logs ==="
	kubectl logs -n monitoring deployment/prometheus-stack-kube-prom-operator --tail=50
	@echo "\n=== Grafana Logs ==="
	kubectl logs -n monitoring deployment/prometheus-stack-grafana --tail=50

monitoring-port-forward:
	@echo "Setting up port forwards for monitoring services..."
	@echo "Grafana will be available at http://localhost:3000"
	@echo "Prometheus will be available at http://localhost:9090"
	@echo "AlertManager will be available at http://localhost:9093"
	@echo "Press Ctrl+C to stop port forwarding"
	kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 & \
	kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 & \
	kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093 & \
	wait
	done

helm-package:
	@echo "Packaging Helm charts..."
	@mkdir -p dist/
	@for chart in charts/*/; do \
		if [ -f "$$chart/Chart.yaml" ]; then \
			echo "Packaging $$chart"; \
			helm package "$$chart" -d dist/ || true; \
		fi \
	done

# Kubernetes-specific targets
k8s-dry-run:
	@echo "Performing Kubernetes dry run..."
	@find manifests -name "*.yaml" -o -name "*.yml" | xargs -I {} kubectl apply --dry-run=client -f {} || true

# Security targets
security-scan:
	@echo "Running security scans..."
	@if command -v trivy >/dev/null 2>&1; then \
		trivy fs . --security-checks vuln,config,secret; \
	else \
		echo "trivy not installed"; \
	fi
	@if command -v trufflehog >/dev/null 2>&1; then \
		trufflehog filesystem . --only-verified; \
	else \
		echo "trufflehog not installed"; \
	fi

# Documentation targets
docs-check:
	@echo "Checking documentation..."
	@if [ ! -f README.md ]; then echo "README.md missing"; fi
	@if [ ! -f plan.md ]; then echo "plan.md missing"; fi
	@echo "Documentation check complete"

# All-in-one targets
check-all: install lint validate test security-scan docs-check
	@echo "All checks completed!"

quick-check: install test-fast lint
	@echo "Quick check completed!"
