# Infrastructure Testing Suite

This directory contains comprehensive tests for the microPlat infrastructure as code stack.

## Overview

The test suite validates:
- **Helm Charts**: Syntax, structure, and best practices
- **Kubernetes Manifests**: YAML validity, resource specifications, and security
- **Docker Builds**: Dockerfile syntax, security, and build validation
- **Integration**: End-to-end workflow and component compatibility
- **Security**: Secret scanning, vulnerability detection, and RBAC validation

## Test Structure

```
tests/
├── conftest.py              # Pytest configuration and fixtures
├── test_helm_charts.py      # Helm chart validation tests
├── test_kubernetes_manifests.py  # K8s manifest tests
├── test_docker_builds.py    # Docker build and security tests
├── test_integration.py      # Integration and workflow tests
├── test_utils.py           # Utility functions and validators
├── requirements.txt        # Test dependencies
└── README.md              # This file
```

## Running Tests

### Prerequisites

1. **Python 3.11+** with pip
2. **Helm 3.x** for chart validation
3. **Docker** for build testing (optional)
4. **kubectl** for manifest validation (optional)

### Installation

```bash
# Install test dependencies
pip install -r tests/requirements.txt

# Or use the Makefile
make install
```

### Running Tests

```bash
# Run all tests
pytest tests/ -v

# Run specific test categories
pytest tests/test_helm_charts.py -v          # Helm charts only
pytest tests/test_kubernetes_manifests.py -v # K8s manifests only
pytest tests/test_docker_builds.py -v        # Docker builds only
pytest tests/test_integration.py -v          # Integration tests only

# Run with coverage
pytest tests/ --cov=. --cov-report=html

# Run fast tests only (exclude slow integration tests)
pytest tests/ -m "not slow"
```

### Using Makefile

```bash
make help                    # Show all available targets
make test                    # Run all tests
make test-fast              # Run fast tests only
make test-helm              # Run Helm chart tests
make test-k8s               # Run Kubernetes manifest tests
make test-docker            # Run Docker build tests
make test-integration       # Run integration tests
make lint                   # Lint all components
make validate               # Validate all infrastructure
make clean                  # Clean up test artifacts
```

## Test Categories

### 1. Helm Chart Tests (`test_helm_charts.py`)

Validates:
- ✅ Chart.yaml structure and required fields
- ✅ values.yaml syntax and validity
- ✅ Template rendering without errors
- ✅ Helm linting compliance
- ✅ Resource limits and requests
- ✅ Chart dependencies
- ✅ Ray cluster specific configurations

**Example:**
```bash
pytest tests/test_helm_charts.py::TestHelmCharts::test_helm_lint -v
```

### 2. Kubernetes Manifest Tests (`test_kubernetes_manifests.py`)

Validates:
- ✅ YAML syntax and structure
- ✅ Required Kubernetes fields (apiVersion, kind, metadata)
- ✅ Resource naming conventions
- ✅ Deployment and Service specifications
- ✅ Resource quotas and limits
- ✅ Security configurations
- ✅ kubeval validation (if available)

**Example:**
```bash
pytest tests/test_kubernetes_manifests.py::TestKubernetesManifests::test_manifests_valid_yaml -v
```

### 3. Docker Build Tests (`test_docker_builds.py`)

Validates:
- ✅ Dockerfile existence and syntax
- ✅ Security best practices
- ✅ Multi-stage build optimization
- ✅ Image labels and metadata
- ✅ Requirements files (requirements.txt, pyproject.toml)
- ✅ Build context validation
- ✅ Security scanning configuration

**Example:**
```bash
pytest tests/test_docker_builds.py::TestDockerBuilds::test_dockerfile_security -v
```

### 4. Integration Tests (`test_integration.py`)

Validates:
- ✅ GitHub workflow syntax and completeness
- ✅ Chart consistency across the platform
- ✅ Resource allocation and limits
- ✅ GitOps workflow compatibility
- ✅ Security configurations
- ✅ Documentation completeness
- ✅ Monitoring and observability setup

**Example:**
```bash
pytest tests/test_integration.py::TestIntegration::test_github_workflow_syntax -v
```

## Test Configuration

### pytest.ini

The `pytest.ini` file in the project root configures:
- Test discovery patterns
- Coverage reporting
- Test markers for categorization
- Output formatting

### Test Markers

Use markers to run specific test categories:

```bash
pytest -m "unit"           # Unit tests only
pytest -m "integration"    # Integration tests only
pytest -m "docker"         # Docker-related tests only
pytest -m "kubernetes"     # Kubernetes-related tests only
pytest -m "not slow"       # Exclude slow tests
```

## Continuous Integration

### GitHub Actions

The test suite integrates with GitHub Actions via `.github/workflows/test-infrastructure.yml`:

- **Helm Chart Testing**: Validates all charts with linting and templating
- **Kubernetes Manifest Testing**: Validates YAML and runs kubeval
- **Docker Build Testing**: Tests Dockerfile syntax and builds
- **Integration Testing**: End-to-end workflow validation
- **Security Scanning**: Trivy and TruffleHog security scans
- **Coverage Reporting**: Uploads coverage to Codecov

### Workflow Triggers

Tests run on:
- Push to `main` or `develop` branches
- Pull requests to `main`
- Daily scheduled runs (2 AM UTC)

## Security Testing

The test suite includes comprehensive security validation:

### Secret Scanning
- Detects hardcoded passwords, API keys, tokens
- Validates secret references use proper Kubernetes mechanisms
- Integrates with TruffleHog for advanced secret detection

### Vulnerability Scanning
- Uses Trivy for filesystem and configuration scanning
- Checks Docker images for known vulnerabilities
- Validates Kubernetes configurations for security issues

### RBAC Validation
- Checks for overly permissive roles
- Validates service account permissions
- Warns about wildcard permissions

## Extending Tests

### Adding New Test Cases

1. **Create test function** in appropriate test file:
```python
def test_my_new_validation(self, helm_charts):
    """Test description."""
    for chart_dir in helm_charts:
        # Your validation logic here
        assert condition, "Error message"
```

2. **Add test markers** if needed:
```python
@pytest.mark.slow
@pytest.mark.integration
def test_slow_integration(self):
    # Test implementation
```

3. **Update documentation** in this README

### Adding New Validators

Add utility functions to `test_utils.py`:

```python
class MyValidator:
    @staticmethod
    def validate_something(data: Dict[str, Any]) -> List[str]:
        """Validate something and return list of errors."""
        errors = []
        # Validation logic
        return errors
```

## Troubleshooting

### Common Issues

1. **Missing Dependencies**
   ```bash
   pip install -r tests/requirements.txt
   ```

2. **Helm Not Found**
   ```bash
   # Install Helm
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

3. **Docker Not Available**
   - Docker tests will be skipped automatically
   - Install Docker Desktop for full test coverage

4. **kubeval Not Found**
   ```bash
   # Install kubeval
   wget https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz
   tar xf kubeval-linux-amd64.tar.gz
   sudo mv kubeval /usr/local/bin
   ```

### Test Failures

1. **Check test output** for specific error messages
2. **Run individual tests** to isolate issues:
   ```bash
   pytest tests/test_helm_charts.py::TestHelmCharts::test_specific_function -v -s
   ```
3. **Use debug mode** for detailed output:
   ```bash
   pytest --pdb tests/test_file.py::test_function
   ```

## Best Practices

### Writing Tests
- Use descriptive test names and docstrings
- Test both positive and negative cases
- Use appropriate test markers
- Keep tests independent and idempotent

### Test Data
- Use fixtures for shared test data
- Avoid hardcoded paths (use `project_root` fixture)
- Clean up test artifacts in teardown

### Performance
- Mark slow tests with `@pytest.mark.slow`
- Use parameterized tests for multiple similar cases
- Cache expensive operations when possible

## Contributing

1. **Add tests** for new infrastructure components
2. **Update documentation** when adding new test categories
3. **Follow naming conventions** for test files and functions
4. **Ensure tests pass** in CI before merging
5. **Add appropriate markers** for test categorization

## Resources

- [Pytest Documentation](https://docs.pytest.org/)
- [Helm Testing Guide](https://helm.sh/docs/topics/chart_tests/)
- [Kubernetes Testing](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-application/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Security Testing Guide](https://owasp.org/www-project-devsecops-guideline/)
