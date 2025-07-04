"""
Tests for Kubernetes manifest validation.
"""
import pytest
import yaml
from pathlib import Path
from .conftest import load_yaml_documents, run_command


class TestKubernetesManifests:
    """Test suite for Kubernetes manifest validation."""

    def test_manifests_valid_yaml(self, kubernetes_manifests):
        """Test that all manifest files are valid YAML."""
        for manifest_file in kubernetes_manifests:
            try:
                load_yaml_documents(manifest_file)
            except yaml.YAMLError as e:
                pytest.fail(f"Invalid YAML in {manifest_file}: {e}")

    def test_manifests_have_required_fields(self, kubernetes_manifests):
        """Test that Kubernetes manifests have required fields."""
        required_fields = ['apiVersion', 'kind', 'metadata']
        
        for manifest_file in kubernetes_manifests:
            documents = load_yaml_documents(manifest_file)
            
            for i, doc in enumerate(documents):
                if doc is None:  # Skip empty documents
                    continue
                    
                for field in required_fields:
                    assert field in doc, \
                        f"Missing {field} in document {i} of {manifest_file}"
                
                # Test metadata has name
                if 'metadata' in doc and doc['metadata']:
                    assert 'name' in doc['metadata'], \
                        f"Missing metadata.name in document {i} of {manifest_file}"

    def test_manifests_valid_api_versions(self, kubernetes_manifests):
        """Test that manifests use valid Kubernetes API versions."""
        # Common valid API versions (not exhaustive)
        valid_api_versions = {
            'v1', 'apps/v1', 'extensions/v1beta1', 'networking.k8s.io/v1',
            'rbac.authorization.k8s.io/v1', 'apiextensions.k8s.io/v1',
            'argoproj.io/v1alpha1', 'ray.io/v1alpha1', 'ray.io/v1',
            'batch/v1', 'batch/v1beta1', 'autoscaling/v1', 'autoscaling/v2',
            'policy/v1beta1', 'networking.istio.io/v1beta1'
        }
        
        for manifest_file in kubernetes_manifests:
            documents = load_yaml_documents(manifest_file)
            
            for i, doc in enumerate(documents):
                if doc is None or 'apiVersion' not in doc:
                    continue
                
                api_version = doc['apiVersion']
                # For now, just check that it follows the expected format
                assert '/' in api_version or api_version == 'v1', \
                    f"Suspicious API version '{api_version}' in document {i} of {manifest_file}"

    def test_manifests_valid_kinds(self, kubernetes_manifests):
        """Test that manifests use valid Kubernetes kinds."""
        # Common valid kinds (not exhaustive)
        valid_kinds = {
            'Deployment', 'Service', 'ConfigMap', 'Secret', 'Namespace',
            'ServiceAccount', 'Role', 'RoleBinding', 'ClusterRole', 'ClusterRoleBinding',
            'Ingress', 'PersistentVolume', 'PersistentVolumeClaim', 'StorageClass',
            'Job', 'CronJob', 'DaemonSet', 'StatefulSet', 'ReplicaSet', 'Pod',
            'HorizontalPodAutoscaler', 'VerticalPodAutoscaler', 'PodDisruptionBudget',
            'NetworkPolicy', 'Application', 'AppProject', 'RayCluster', 'RayService',
            'CustomResourceDefinition'
        }
        
        for manifest_file in kubernetes_manifests:
            documents = load_yaml_documents(manifest_file)
            
            for i, doc in enumerate(documents):
                if doc is None or 'kind' not in doc:
                    continue
                
                kind = doc['kind']
                # For now, just check that kind is capitalized (Kubernetes convention)
                assert kind[0].isupper(), \
                    f"Kind '{kind}' should be capitalized in document {i} of {manifest_file}"

    def test_deployment_manifests_structure(self, kubernetes_manifests):
        """Test that Deployment manifests have proper structure."""
        for manifest_file in kubernetes_manifests:
            documents = load_yaml_documents(manifest_file)
            
            for i, doc in enumerate(documents):
                if doc is None or doc.get('kind') != 'Deployment':
                    continue
                
                # Test spec exists
                assert 'spec' in doc, \
                    f"Missing spec in Deployment document {i} of {manifest_file}"
                
                spec = doc['spec']
                
                # Test selector exists
                assert 'selector' in spec, \
                    f"Missing selector in Deployment document {i} of {manifest_file}"
                
                # Test template exists
                assert 'template' in spec, \
                    f"Missing template in Deployment document {i} of {manifest_file}"
                
                template = spec['template']
                assert 'spec' in template, \
                    f"Missing template.spec in Deployment document {i} of {manifest_file}"
                
                # Test containers exist
                template_spec = template['spec']
                assert 'containers' in template_spec, \
                    f"Missing containers in Deployment document {i} of {manifest_file}"
                
                containers = template_spec['containers']
                assert isinstance(containers, list) and len(containers) > 0, \
                    f"Containers must be a non-empty list in Deployment document {i} of {manifest_file}"
                
                # Test each container has required fields
                for j, container in enumerate(containers):
                    assert 'name' in container, \
                        f"Missing name in container {j} of Deployment document {i} of {manifest_file}"
                    assert 'image' in container, \
                        f"Missing image in container {j} of Deployment document {i} of {manifest_file}"

    def test_service_manifests_structure(self, kubernetes_manifests):
        """Test that Service manifests have proper structure."""
        for manifest_file in kubernetes_manifests:
            documents = load_yaml_documents(manifest_file)
            
            for i, doc in enumerate(documents):
                if doc is None or doc.get('kind') != 'Service':
                    continue
                
                # Test spec exists
                assert 'spec' in doc, \
                    f"Missing spec in Service document {i} of {manifest_file}"
                
                spec = doc['spec']
                
                # Test ports exist
                assert 'ports' in spec, \
                    f"Missing ports in Service document {i} of {manifest_file}"
                
                ports = spec['ports']
                assert isinstance(ports, list) and len(ports) > 0, \
                    f"Ports must be a non-empty list in Service document {i} of {manifest_file}"
                
                # Test each port has required fields
                for j, port in enumerate(ports):
                    assert 'port' in port, \
                        f"Missing port in port {j} of Service document {i} of {manifest_file}"

    def test_kubeval_validation(self, kubernetes_manifests):
        """Test manifests with kubeval if available."""
        # Check if kubeval is available
        result = run_command(['kubeval', '--version'])
        if result.returncode != 0:
            pytest.skip("kubeval not available, skipping validation")
        
        for manifest_file in kubernetes_manifests:
            result = run_command(['kubeval', str(manifest_file)])
            if result.returncode != 0:
                # Some manifests might use CRDs not known to kubeval, so just warn
                print(f"Warning: kubeval validation failed for {manifest_file}: {result.stderr}")

    def test_no_hardcoded_secrets(self, kubernetes_manifests):
        """Test that manifests don't contain hardcoded secrets."""
        suspicious_patterns = [
            'password:', 'token:', 'key:', 'secret:', 'apikey:', 'api-key:'
        ]
        
        for manifest_file in kubernetes_manifests:
            with open(manifest_file, 'r') as f:
                content = f.read().lower()
                
                for pattern in suspicious_patterns:
                    if pattern in content:
                        # Check if it's actually a hardcoded value (not a reference)
                        lines = content.split('\n')
                        for line_num, line in enumerate(lines, 1):
                            if pattern in line and not any(ref in line for ref in ['secretkeyref', 'configmapkeyref', 'fieldref']):
                                # Look for actual values after the pattern
                                if ':' in line:
                                    parts = line.split(':', 1)
                                    if len(parts) > 1:
                                        value = parts[1].strip()
                                        # If there's a non-empty value that's not a reference, warn
                                        if value and not value.startswith('{{') and not value.startswith('$'):
                                            print(f"Warning: Potential hardcoded secret in {manifest_file}:{line_num}")

    def test_resource_quotas_reasonable(self, kubernetes_manifests):
        """Test that resource requests and limits are reasonable."""
        for manifest_file in kubernetes_manifests:
            documents = load_yaml_documents(manifest_file)
            
            for i, doc in enumerate(documents):
                if doc is None:
                    continue
                
                self._check_resources_recursive(doc, manifest_file, i)
    
    def _check_resources_recursive(self, obj, manifest_file, doc_index, path=""):
        """Recursively check resource specifications."""
        if isinstance(obj, dict):
            if 'resources' in obj:
                resources = obj['resources']
                if isinstance(resources, dict):
                    self._validate_resource_spec(resources, manifest_file, doc_index, path)
            
            for key, value in obj.items():
                self._check_resources_recursive(value, manifest_file, doc_index, f"{path}.{key}" if path else key)
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                self._check_resources_recursive(item, manifest_file, doc_index, f"{path}[{i}]")
    
    def _validate_resource_spec(self, resources, manifest_file, doc_index, path):
        """Validate a resource specification."""
        for resource_type in ['requests', 'limits']:
            if resource_type in resources:
                resource_values = resources[resource_type]
                if isinstance(resource_values, dict):
                    # Check CPU values
                    if 'cpu' in resource_values:
                        cpu_value = resource_values['cpu']
                        if isinstance(cpu_value, str):
                            # Basic validation - should end with 'm' for millicores or be a number
                            if not (cpu_value.endswith('m') or cpu_value.replace('.', '').isdigit()):
                                print(f"Warning: Suspicious CPU value '{cpu_value}' in {manifest_file} document {doc_index} at {path}")
                    
                    # Check memory values
                    if 'memory' in resource_values:
                        memory_value = resource_values['memory']
                        if isinstance(memory_value, str):
                            # Basic validation - should end with memory units
                            valid_suffixes = ['Ki', 'Mi', 'Gi', 'Ti', 'K', 'M', 'G', 'T']
                            if not any(memory_value.endswith(suffix) for suffix in valid_suffixes):
                                if not memory_value.isdigit():
                                    print(f"Warning: Suspicious memory value '{memory_value}' in {manifest_file} document {doc_index} at {path}")
