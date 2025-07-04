"""
Utility functions for testing infrastructure components.
"""
import subprocess
import yaml
import json
from pathlib import Path
from typing import Dict, List, Any, Optional


class KubernetesValidator:
    """Utility class for validating Kubernetes resources."""
    
    @staticmethod
    def validate_resource_names(resource: Dict[str, Any]) -> List[str]:
        """Validate Kubernetes resource naming conventions."""
        errors = []
        
        if 'metadata' not in resource:
            return ['Missing metadata section']
        
        metadata = resource['metadata']
        name = metadata.get('name', '')
        
        # Check name format (RFC 1123)
        if not name:
            errors.append('Resource name is empty')
        elif len(name) > 253:
            errors.append(f'Resource name too long: {len(name)} > 253')
        elif not name.replace('-', '').replace('.', '').isalnum():
            errors.append(f'Resource name contains invalid characters: {name}')
        elif name.startswith('-') or name.endswith('-'):
            errors.append(f'Resource name cannot start or end with hyphen: {name}')
        
        return errors
    
    @staticmethod
    def validate_labels(resource: Dict[str, Any]) -> List[str]:
        """Validate Kubernetes labels."""
        errors = []
        
        metadata = resource.get('metadata', {})
        labels = metadata.get('labels', {})
        
        for key, value in labels.items():
            # Validate label key
            if len(key) > 63:
                errors.append(f'Label key too long: {key}')
            
            # Validate label value
            if len(str(value)) > 63:
                errors.append(f'Label value too long: {value}')
        
        return errors
    
    @staticmethod
    def validate_annotations(resource: Dict[str, Any]) -> List[str]:
        """Validate Kubernetes annotations."""
        errors = []
        
        metadata = resource.get('metadata', {})
        annotations = metadata.get('annotations', {})
        
        for key, value in annotations.items():
            # Validate annotation key format
            if '/' in key:
                prefix, name = key.rsplit('/', 1)
                if len(prefix) > 253:
                    errors.append(f'Annotation prefix too long: {prefix}')
                if len(name) > 63:
                    errors.append(f'Annotation name too long: {name}')
            elif len(key) > 63:
                errors.append(f'Annotation key too long: {key}')
        
        return errors


class HelmValidator:
    """Utility class for validating Helm charts."""
    
    @staticmethod
    def validate_chart_version(version: str) -> List[str]:
        """Validate Helm chart version follows semantic versioning."""
        errors = []
        
        if not version:
            return ['Version is empty']
        
        # Basic semantic versioning check
        parts = version.split('.')
        if len(parts) < 2:
            errors.append(f'Version should have at least major.minor: {version}')
        
        for part in parts:
            if not part.isdigit():
                # Allow pre-release versions like 1.0.0-alpha
                if '-' in part:
                    base_part = part.split('-')[0]
                    if not base_part.isdigit():
                        errors.append(f'Invalid version part: {part}')
                else:
                    errors.append(f'Invalid version part: {part}')
        
        return errors
    
    @staticmethod
    def validate_dependencies(dependencies: List[Dict[str, Any]]) -> List[str]:
        """Validate Helm chart dependencies."""
        errors = []
        
        for i, dep in enumerate(dependencies):
            if 'name' not in dep:
                errors.append(f'Dependency {i} missing name')
            if 'version' not in dep:
                errors.append(f'Dependency {i} missing version')
            if 'repository' not in dep:
                errors.append(f'Dependency {i} missing repository')
            
            # Validate repository URL
            if 'repository' in dep:
                repo = dep['repository']
                if not (repo.startswith('http://') or repo.startswith('https://') or repo.startswith('oci://')):
                    if repo not in ['@stable', '@incubator']:  # Allow alias repositories
                        errors.append(f'Invalid repository URL: {repo}')
        
        return errors


class DockerValidator:
    """Utility class for validating Docker configurations."""
    
    @staticmethod
    def validate_dockerfile_instructions(content: str) -> List[str]:
        """Validate Dockerfile instructions."""
        errors = []
        lines = content.strip().split('\n')
        
        # Remove comments and empty lines
        instructions = []
        for line in lines:
            line = line.strip()
            if line and not line.startswith('#'):
                instructions.append(line)
        
        if not instructions:
            return ['Dockerfile is empty']
        
        # First instruction should be FROM
        if not instructions[0].upper().startswith('FROM'):
            errors.append('First instruction should be FROM')
        
        # Check for common security issues
        for i, instruction in enumerate(instructions):
            upper_instruction = instruction.upper()
            
            # Check for running as root
            if upper_instruction.startswith('USER ROOT'):
                errors.append(f'Line {i+1}: Running as root user')
            
            # Check for ADD instead of COPY for local files
            if upper_instruction.startswith('ADD ') and 'http' not in instruction.lower():
                errors.append(f'Line {i+1}: Use COPY instead of ADD for local files')
            
            # Check for missing --no-cache-dir in pip installs
            if 'pip install' in instruction.lower() and '--no-cache-dir' not in instruction.lower():
                errors.append(f'Line {i+1}: pip install should use --no-cache-dir')
        
        return errors
    
    @staticmethod
    def validate_image_tags(tag: str) -> List[str]:
        """Validate Docker image tags."""
        errors = []
        
        if not tag:
            errors.append('Image tag is empty')
            return errors
        
        if tag == 'latest':
            errors.append('Using "latest" tag is not recommended for production')
        
        # Check tag format
        if len(tag) > 128:
            errors.append(f'Tag too long: {len(tag)} > 128')
        
        # Basic character validation
        invalid_chars = ['/', ':', ' ', '\t', '\n']
        for char in invalid_chars:
            if char in tag:
                errors.append(f'Tag contains invalid character: {char}')
        
        return errors


class SecurityValidator:
    """Utility class for security validation."""
    
    @staticmethod
    def scan_for_secrets(content: str, filename: str = '') -> List[str]:
        """Scan content for potential secrets."""
        warnings = []
        
        # Common secret patterns
        secret_patterns = [
            ('password', r'password\s*[:=]\s*["\']?([^"\'\s]+)'),
            ('api_key', r'api[_-]?key\s*[:=]\s*["\']?([^"\'\s]+)'),
            ('token', r'token\s*[:=]\s*["\']?([^"\'\s]+)'),
            ('secret', r'secret\s*[:=]\s*["\']?([^"\'\s]+)'),
        ]
        
        lines = content.split('\n')
        for line_num, line in enumerate(lines, 1):
            line_lower = line.lower()
            
            for pattern_name, pattern in secret_patterns:
                if pattern_name in line_lower:
                    # Check if it's likely a hardcoded secret
                    if '=' in line or ':' in line:
                        # Skip if it's clearly a reference or placeholder
                        if any(ref in line_lower for ref in ['secretkeyref', 'configmapkeyref', '{{', '${']):
                            continue
                        
                        warnings.append(f'{filename}:{line_num} - Potential {pattern_name}: {line.strip()}')
        
        return warnings
    
    @staticmethod
    def validate_rbac_permissions(resource: Dict[str, Any]) -> List[str]:
        """Validate RBAC permissions are not overly permissive."""
        warnings = []
        
        if resource.get('kind') in ['Role', 'ClusterRole']:
            rules = resource.get('rules', [])
            
            for rule in rules:
                # Check for wildcard permissions
                if '*' in rule.get('verbs', []):
                    warnings.append('Wildcard verb permissions detected')
                
                if '*' in rule.get('resources', []):
                    warnings.append('Wildcard resource permissions detected')
                
                # Check for dangerous verbs
                dangerous_verbs = ['create', 'delete', 'deletecollection', 'patch', 'update']
                rule_verbs = rule.get('verbs', [])
                
                if any(verb in rule_verbs for verb in dangerous_verbs):
                    resources = rule.get('resources', [])
                    if 'secrets' in resources:
                        warnings.append('Dangerous permissions on secrets detected')
                    if 'pods' in resources and 'create' in rule_verbs:
                        warnings.append('Pod creation permissions detected')
        
        return warnings


def run_command_with_timeout(cmd: List[str], timeout: int = 30, cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
    """Run a command with timeout."""
    try:
        return subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(
            cmd, 1, '', f'Command timed out after {timeout} seconds'
        )


def load_yaml_safely(file_path: Path) -> Any:
    """Load YAML file with error handling."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except yaml.YAMLError as e:
        raise ValueError(f'Invalid YAML in {file_path}: {e}')
    except Exception as e:
        raise ValueError(f'Error reading {file_path}: {e}')


def validate_json_schema(data: Dict[str, Any], schema: Dict[str, Any]) -> List[str]:
    """Validate data against JSON schema (basic implementation)."""
    errors = []
    
    # Basic required fields validation
    if 'required' in schema:
        for field in schema['required']:
            if field not in data:
                errors.append(f'Missing required field: {field}')
    
    # Basic type validation
    if 'properties' in schema:
        for field, field_schema in schema['properties'].items():
            if field in data:
                expected_type = field_schema.get('type')
                actual_value = data[field]
                
                if expected_type == 'string' and not isinstance(actual_value, str):
                    errors.append(f'Field {field} should be string, got {type(actual_value).__name__}')
                elif expected_type == 'number' and not isinstance(actual_value, (int, float)):
                    errors.append(f'Field {field} should be number, got {type(actual_value).__name__}')
                elif expected_type == 'boolean' and not isinstance(actual_value, bool):
                    errors.append(f'Field {field} should be boolean, got {type(actual_value).__name__}')
                elif expected_type == 'array' and not isinstance(actual_value, list):
                    errors.append(f'Field {field} should be array, got {type(actual_value).__name__}')
                elif expected_type == 'object' and not isinstance(actual_value, dict):
                    errors.append(f'Field {field} should be object, got {type(actual_value).__name__}')
    
    return errors
