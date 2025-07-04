"""
Integration tests for the ML platform infrastructure.
"""
import pytest
import yaml
import time
from pathlib import Path
from .conftest import load_yaml_file, run_command


class TestIntegration:
    """Integration test suite for the ML platform."""

    def test_github_workflow_syntax(self, project_root):
        """Test that GitHub workflow files are valid YAML."""
        workflows_dir = project_root / ".github" / "workflows"
        
        if not workflows_dir.exists():
            pytest.skip("No GitHub workflows directory found")
        
        workflow_files = list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))
        
        for workflow_file in workflow_files:
            try:
                workflow_data = load_yaml_file(workflow_file)
                
                # Basic workflow structure validation
                assert 'name' in workflow_data, f"Missing 'name' in {workflow_file.name}"
                assert 'on' in workflow_data, f"Missing 'on' trigger in {workflow_file.name}"
                assert 'jobs' in workflow_data, f"Missing 'jobs' in {workflow_file.name}"
                
                # Validate jobs structure
                jobs = workflow_data['jobs']
                assert isinstance(jobs, dict), f"Jobs must be a dictionary in {workflow_file.name}"
                
                for job_name, job_config in jobs.items():
                    assert 'runs-on' in job_config, f"Missing 'runs-on' in job '{job_name}' in {workflow_file.name}"
                    assert 'steps' in job_config, f"Missing 'steps' in job '{job_name}' in {workflow_file.name}"
                    
                    steps = job_config['steps']
                    assert isinstance(steps, list), f"Steps must be a list in job '{job_name}' in {workflow_file.name}"
                    
            except yaml.YAMLError as e:
                pytest.fail(f"Invalid YAML in {workflow_file.name}: {e}")

    def test_build_push_workflow_completeness(self, project_root):
        """Test that the build-push workflow covers all expected images."""
        workflow_file = project_root / ".github" / "workflows" / "build-push.yml"
        
        if not workflow_file.exists():
            pytest.skip("build-push.yml workflow not found")
        
        workflow_data = load_yaml_file(workflow_file)
        
        # Check matrix strategy
        jobs = workflow_data.get('jobs', {})
        build_job = jobs.get('build', {})
        strategy = build_job.get('strategy', {})
        matrix = strategy.get('matrix', {})
        
        expected_images = ['notebook', 'trainer', 'serve']
        actual_images = matrix.get('image', [])
        
        for expected_image in expected_images:
            assert expected_image in actual_images, \
                f"Image '{expected_image}' missing from build matrix"

    def test_helm_chart_consistency(self, charts_dir):
        """Test consistency between Helm charts and expected structure."""
        expected_charts = ['ray-cluster', 'jupyterhub', 'mlflow', 'ray-operator']
        
        for chart_name in expected_charts:
            chart_dir = charts_dir / chart_name
            if not chart_dir.exists():
                print(f"Warning: Expected chart '{chart_name}' not found")
                continue
            
            chart_yaml = chart_dir / "Chart.yaml"
            values_yaml = chart_dir / "values.yaml"
            
            if chart_yaml.exists():
                chart_data = load_yaml_file(chart_yaml)
                # Chart name should match directory name
                if chart_data.get('name') != chart_name:
                    print(f"Warning: Chart name '{chart_data.get('name')}' doesn't match directory '{chart_name}'")

    def test_ray_cluster_integration(self, charts_dir):
        """Test Ray cluster chart integration requirements."""
        ray_chart_dir = charts_dir / "ray-cluster"
        if not ray_chart_dir.exists():
            pytest.skip("Ray cluster chart not found")
        
        values_yaml = ray_chart_dir / "values.yaml"
        values_data = load_yaml_file(values_yaml)
        
        # Test Ray version consistency
        ray_version = values_data.get('spec', {}).get('rayVersion')
        image_tag = values_data.get('image', {}).get('tag', '')
        
        if ray_version and image_tag:
            # Extract version from image tag (e.g., "2.47.0-py311-cpu" -> "2.47.0")
            if '-' in image_tag:
                image_version = image_tag.split('-')[0]
                assert ray_version == image_version, \
                    f"Ray version mismatch: spec.rayVersion={ray_version}, image tag version={image_version}"

    def test_resource_consistency(self, charts_dir, kubernetes_manifests):
        """Test resource allocation consistency across charts and manifests."""
        total_cpu_requests = 0
        total_memory_requests = 0
        
        # Collect resource requests from Helm charts
        for chart_dir in charts_dir.iterdir():
            if not chart_dir.is_dir():
                continue
            
            values_yaml = chart_dir / "values.yaml"
            if values_yaml.exists():
                values_data = load_yaml_file(values_yaml)
                cpu, memory = self._extract_resources(values_data)
                total_cpu_requests += cpu
                total_memory_requests += memory
        
        # Collect resource requests from manifests
        for manifest_file in kubernetes_manifests:
            documents = yaml.safe_load_all(open(manifest_file, 'r'))
            for doc in documents:
                if doc and doc.get('kind') in ['Deployment', 'StatefulSet', 'DaemonSet']:
                    cpu, memory = self._extract_resources(doc)
                    total_cpu_requests += cpu
                    total_memory_requests += memory
        
        # Basic sanity check - total requests shouldn't be excessive
        if total_cpu_requests > 20:  # 20 CPU cores
            print(f"Warning: High total CPU requests: {total_cpu_requests}")
        
        if total_memory_requests > 50 * 1024:  # 50 GB in MB
            print(f"Warning: High total memory requests: {total_memory_requests}MB")

    def _extract_resources(self, data, cpu_total=0, memory_total=0):
        """Extract CPU and memory requests from nested data structure."""
        if isinstance(data, dict):
            if 'resources' in data:
                resources = data['resources']
                if isinstance(resources, dict) and 'requests' in resources:
                    requests = resources['requests']
                    if isinstance(requests, dict):
                        # Parse CPU
                        if 'cpu' in requests:
                            cpu_str = str(requests['cpu'])
                            if cpu_str.endswith('m'):
                                cpu_total += int(cpu_str[:-1]) / 1000
                            else:
                                cpu_total += float(cpu_str)
                        
                        # Parse memory
                        if 'memory' in requests:
                            memory_str = str(requests['memory'])
                            if memory_str.endswith('Mi'):
                                memory_total += int(memory_str[:-2])
                            elif memory_str.endswith('Gi'):
                                memory_total += int(memory_str[:-2]) * 1024
                            elif memory_str.endswith('Ki'):
                                memory_total += int(memory_str[:-2]) / 1024
            
            for value in data.values():
                cpu_total, memory_total = self._extract_resources(value, cpu_total, memory_total)
        
        elif isinstance(data, list):
            for item in data:
                cpu_total, memory_total = self._extract_resources(item, cpu_total, memory_total)
        
        return cpu_total, memory_total

    def test_gitops_workflow_compatibility(self, project_root):
        """Test GitOps workflow compatibility."""
        # Check for Argo CD application manifests
        manifests_dir = project_root / "manifests"
        argo_dir = manifests_dir / "argo"
        
        if argo_dir.exists():
            app_files = list(argo_dir.glob("**/*.yaml")) + list(argo_dir.glob("**/*.yml"))
            
            for app_file in app_files:
                documents = yaml.safe_load_all(open(app_file, 'r'))
                for doc in documents:
                    if doc and doc.get('kind') == 'Application':
                        # Validate Argo CD Application structure
                        assert 'spec' in doc, f"Missing spec in Application {app_file}"
                        spec = doc['spec']
                        
                        assert 'source' in spec, f"Missing source in Application {app_file}"
                        assert 'destination' in spec, f"Missing destination in Application {app_file}"
                        
                        source = spec['source']
                        assert 'repoURL' in source, f"Missing repoURL in Application {app_file}"
                        assert 'path' in source, f"Missing path in Application {app_file}"

    def test_security_configurations(self, project_root):
        """Test security-related configurations."""
        # Check for security policies
        security_files = [
            ".github/dependabot.yml",
            ".github/security.md",
            "SECURITY.md"
        ]
        
        for security_file in security_files:
            file_path = project_root / security_file
            if file_path.exists():
                print(f"Info: Found security file: {security_file}")
        
        # Check GitHub workflow for security scanning
        workflows_dir = project_root / ".github" / "workflows"
        if workflows_dir.exists():
            workflow_files = list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))
            
            security_scanning = False
            for workflow_file in workflow_files:
                with open(workflow_file, 'r') as f:
                    content = f.read()
                
                # Look for security scanning actions
                security_actions = [
                    'github/codeql-action',
                    'securecodewarrior/github-action-add-sarif',
                    'docker/scout-action'
                ]
                
                for action in security_actions:
                    if action in content:
                        security_scanning = True
                        break
            
            if not security_scanning:
                print("Warning: No security scanning detected in GitHub workflows")

    def test_documentation_completeness(self, project_root):
        """Test that documentation is complete and up-to-date."""
        readme_file = project_root / "README.md"
        assert readme_file.exists(), "README.md file missing"
        
        with open(readme_file, 'r') as f:
            readme_content = f.read()
        
        # Check for essential sections
        essential_sections = [
            'installation', 'setup', 'usage', 'deployment'
        ]
        
        readme_lower = readme_content.lower()
        for section in essential_sections:
            if section not in readme_lower:
                print(f"Warning: README.md missing section about '{section}'")
        
        # Check if plan.md exists and is referenced
        plan_file = project_root / "plan.md"
        if plan_file.exists():
            if 'plan.md' not in readme_content:
                print("Warning: plan.md exists but not referenced in README.md")

    def test_environment_configuration(self, project_root):
        """Test environment-specific configurations."""
        # Check for environment-specific values files
        charts_dir = project_root / "charts"
        
        for chart_dir in charts_dir.iterdir():
            if not chart_dir.is_dir():
                continue
            
            # Look for environment-specific values files
            env_files = list(chart_dir.glob("values-*.yaml")) + list(chart_dir.glob("values-*.yml"))
            
            if env_files:
                for env_file in env_files:
                    try:
                        load_yaml_file(env_file)
                    except yaml.YAMLError as e:
                        pytest.fail(f"Invalid YAML in {env_file}: {e}")

    def test_monitoring_configuration(self, charts_dir, kubernetes_manifests):
        """Test monitoring and observability configurations."""
        # Check for Prometheus/Grafana configurations
        monitoring_keywords = [
            'prometheus', 'grafana', 'alertmanager', 'servicemonitor',
            'prometheusrule', 'monitoring'
        ]
        
        monitoring_found = False
        
        # Check in Helm charts
        for chart_dir in charts_dir.iterdir():
            if not chart_dir.is_dir():
                continue
            
            chart_name = chart_dir.name.lower()
            if any(keyword in chart_name for keyword in monitoring_keywords):
                monitoring_found = True
                break
        
        # Check in manifests
        if not monitoring_found:
            for manifest_file in kubernetes_manifests:
                with open(manifest_file, 'r') as f:
                    content = f.read().lower()
                
                if any(keyword in content for keyword in monitoring_keywords):
                    monitoring_found = True
                    break
        
        if not monitoring_found:
            print("Warning: No monitoring/observability configuration detected")
