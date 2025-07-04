"""
Tests for Helm charts validation and linting.
"""
import pytest
import yaml
from pathlib import Path
from .conftest import load_yaml_file, run_command


class TestHelmCharts:
    """Test suite for Helm chart validation."""

    def test_chart_yaml_exists(self, helm_charts):
        """Test that each chart has a Chart.yaml file."""
        for chart_dir in helm_charts:
            chart_yaml = chart_dir / "Chart.yaml"
            assert chart_yaml.exists(), f"Chart.yaml missing in {chart_dir.name}"

    def test_chart_yaml_structure(self, helm_charts):
        """Test that Chart.yaml files have required fields."""
        required_fields = ['apiVersion', 'name', 'version', 'description']
        
        for chart_dir in helm_charts:
            chart_yaml = chart_dir / "Chart.yaml"
            chart_data = load_yaml_file(chart_yaml)
            
            for field in required_fields:
                assert field in chart_data, f"Missing {field} in {chart_dir.name}/Chart.yaml"
            
            # Validate apiVersion
            assert chart_data['apiVersion'] in ['v1', 'v2'], \
                f"Invalid apiVersion in {chart_dir.name}/Chart.yaml"
            
            # Validate version format (semantic versioning)
            version = chart_data['version']
            version_parts = version.split('.')
            assert len(version_parts) >= 2, \
                f"Invalid version format in {chart_dir.name}/Chart.yaml"

    def test_values_yaml_exists(self, helm_charts):
        """Test that each chart has a values.yaml file."""
        for chart_dir in helm_charts:
            values_yaml = chart_dir / "values.yaml"
            assert values_yaml.exists(), f"values.yaml missing in {chart_dir.name}"

    def test_values_yaml_valid(self, helm_charts):
        """Test that values.yaml files are valid YAML."""
        for chart_dir in helm_charts:
            values_yaml = chart_dir / "values.yaml"
            try:
                load_yaml_file(values_yaml)
            except yaml.YAMLError as e:
                pytest.fail(f"Invalid YAML in {chart_dir.name}/values.yaml: {e}")

    def test_templates_directory_exists(self, helm_charts):
        """Test that each chart has a templates directory."""
        for chart_dir in helm_charts:
            templates_dir = chart_dir / "templates"
            assert templates_dir.exists() and templates_dir.is_dir(), \
                f"templates directory missing in {chart_dir.name}"

    def test_helm_lint(self, helm_charts):
        """Test that Helm charts pass linting."""
        for chart_dir in helm_charts:
            result = run_command(['helm', 'lint', str(chart_dir)])
            assert result.returncode == 0, \
                f"Helm lint failed for {chart_dir.name}: {result.stderr}"

    def test_helm_template_render(self, helm_charts):
        """Test that Helm charts can be templated without errors."""
        for chart_dir in helm_charts:
            result = run_command(['helm', 'template', 'test', str(chart_dir)])
            assert result.returncode == 0, \
                f"Helm template failed for {chart_dir.name}: {result.stderr}"

    def test_ray_cluster_chart_specific(self, charts_dir):
        """Test Ray cluster chart specific requirements."""
        ray_chart_dir = charts_dir / "ray-cluster"
        if not ray_chart_dir.exists():
            pytest.skip("Ray cluster chart not found")
        
        values_yaml = ray_chart_dir / "values.yaml"
        values_data = load_yaml_file(values_yaml)
        
        # Test image configuration
        assert 'image' in values_data, "Image configuration missing"
        assert 'repository' in values_data['image'], "Image repository missing"
        assert 'tag' in values_data['image'], "Image tag missing"
        
        # Test Ray cluster spec
        assert 'spec' in values_data, "Ray cluster spec missing"
        assert 'rayVersion' in values_data['spec'], "Ray version missing"
        assert 'headGroupSpec' in values_data['spec'], "Head group spec missing"
        assert 'workerGroupSpecs' in values_data['spec'], "Worker group specs missing"

    def test_chart_dependencies(self, helm_charts):
        """Test that chart dependencies are properly defined."""
        for chart_dir in helm_charts:
            chart_yaml = chart_dir / "Chart.yaml"
            chart_data = load_yaml_file(chart_yaml)
            
            if 'dependencies' in chart_data:
                for dep in chart_data['dependencies']:
                    required_dep_fields = ['name', 'version', 'repository']
                    for field in required_dep_fields:
                        assert field in dep, \
                            f"Missing {field} in dependency of {chart_dir.name}"

    def test_resource_limits_defined(self, helm_charts):
        """Test that resource limits are defined in values.yaml."""
        for chart_dir in helm_charts:
            values_yaml = chart_dir / "values.yaml"
            values_data = load_yaml_file(values_yaml)
            
            # Check if resources are defined somewhere in the values
            def has_resources(data, path=""):
                if isinstance(data, dict):
                    if 'resources' in data:
                        resources = data['resources']
                        if isinstance(resources, dict):
                            # Should have either limits or requests
                            has_limits_or_requests = 'limits' in resources or 'requests' in resources
                            if has_limits_or_requests:
                                return True
                    
                    for key, value in data.items():
                        if has_resources(value, f"{path}.{key}" if path else key):
                            return True
                elif isinstance(data, list):
                    for i, item in enumerate(data):
                        if has_resources(item, f"{path}[{i}]"):
                            return True
                return False
            
            # For now, just warn if no resources are found
            if not has_resources(values_data):
                print(f"Warning: No resource limits/requests found in {chart_dir.name}")
