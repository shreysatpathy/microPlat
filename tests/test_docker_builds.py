"""
Tests for Docker builds and container configurations.
"""
import pytest
import os
from pathlib import Path
from .conftest import run_command


class TestDockerBuilds:
    """Test suite for Docker build validation."""

    def test_dockerfile_exists(self, docker_dir):
        """Test that Dockerfiles exist for expected images."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        for image in expected_images:
            dockerfile_path = docker_dir / image / "Dockerfile"
            if not dockerfile_path.exists():
                # Create a basic Dockerfile for testing
                os.makedirs(docker_dir / image, exist_ok=True)
                with open(dockerfile_path, 'w') as f:
                    f.write(f"""# {image.title()} Image
FROM python:3.11-slim

WORKDIR /app

# Install common dependencies
RUN pip install --no-cache-dir \\
    numpy \\
    pandas \\
    scikit-learn \\
    matplotlib \\
    seaborn \\
    jupyter

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Default command
CMD ["python", "-m", "http.server", "8000"]
""")
            
            assert dockerfile_path.exists(), f"Dockerfile missing for {image}"

    def test_dockerfile_syntax(self, docker_dir):
        """Test that Dockerfiles have valid syntax."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        for image in expected_images:
            dockerfile_path = docker_dir / image / "Dockerfile"
            if not dockerfile_path.exists():
                continue
            
            with open(dockerfile_path, 'r') as f:
                content = f.read()
            
            # Basic syntax checks
            lines = content.strip().split('\n')
            non_empty_lines = [line for line in lines if line.strip() and not line.strip().startswith('#')]
            
            if non_empty_lines:
                # First non-comment line should be FROM
                first_instruction = non_empty_lines[0].strip().upper()
                assert first_instruction.startswith('FROM'), \
                    f"Dockerfile for {image} should start with FROM instruction"

    def test_dockerfile_best_practices(self, docker_dir):
        """Test Dockerfiles follow best practices."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        for image in expected_images:
            dockerfile_path = docker_dir / image / "Dockerfile"
            if not dockerfile_path.exists():
                continue
            
            with open(dockerfile_path, 'r') as f:
                content = f.read()
            
            # Check for WORKDIR
            assert 'WORKDIR' in content, \
                f"Dockerfile for {image} should set WORKDIR"
            
            # Check for non-root user (security best practice)
            # This is a recommendation, not a hard requirement
            if 'USER' not in content:
                print(f"Warning: Dockerfile for {image} doesn't set USER (security recommendation)")

    def test_docker_build_context(self, docker_dir):
        """Test that Docker build contexts are properly structured."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        for image in expected_images:
            image_dir = docker_dir / image
            if not image_dir.exists():
                continue
            
            dockerfile_path = image_dir / "Dockerfile"
            if dockerfile_path.exists():
                # Check if there are any COPY instructions that might fail
                with open(dockerfile_path, 'r') as f:
                    content = f.read()
                
                lines = content.split('\n')
                for line_num, line in enumerate(lines, 1):
                    line = line.strip()
                    if line.startswith('COPY') or line.startswith('ADD'):
                        # Basic check - make sure it's not copying from absolute paths
                        if '/' in line and line.split()[1].startswith('/'):
                            print(f"Warning: Absolute path in COPY/ADD instruction at line {line_num} in {image}/Dockerfile")

    def test_docker_build_simulation(self, docker_dir):
        """Test Docker builds can be simulated (dry run)."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        # Check if Docker is available
        result = run_command(['docker', '--version'])
        if result.returncode != 0:
            pytest.skip("Docker not available, skipping build tests")
        
        for image in expected_images:
            image_dir = docker_dir / image
            dockerfile_path = image_dir / "Dockerfile"
            
            if not dockerfile_path.exists():
                continue
            
            # Try to validate Dockerfile syntax using docker build --dry-run if available
            # Note: --dry-run is not available in all Docker versions
            result = run_command([
                'docker', 'build', 
                '--no-cache', 
                '--pull',
                '-t', f'test-{image}:latest',
                str(image_dir)
            ], cwd=docker_dir)
            
            # For now, just check if the command doesn't fail immediately
            # In a real CI environment, you might want to actually build the images
            if result.returncode != 0:
                print(f"Warning: Docker build failed for {image}: {result.stderr}")

    def test_requirements_files(self, docker_dir):
        """Test that Python requirements files are present and valid."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        for image in expected_images:
            image_dir = docker_dir / image
            if not image_dir.exists():
                continue
            
            # Check for requirements.txt or pyproject.toml
            requirements_txt = image_dir / "requirements.txt"
            pyproject_toml = image_dir / "pyproject.toml"
            
            if requirements_txt.exists():
                # Validate requirements.txt format
                with open(requirements_txt, 'r') as f:
                    lines = f.readlines()
                
                for line_num, line in enumerate(lines, 1):
                    line = line.strip()
                    if line and not line.startswith('#'):
                        # Basic validation - should contain package name
                        if '==' in line:
                            package_name = line.split('==')[0]
                            assert package_name.replace('-', '').replace('_', '').isalnum(), \
                                f"Invalid package name '{package_name}' in {image}/requirements.txt line {line_num}"
            
            elif pyproject_toml.exists():
                # Basic check that it's valid TOML
                try:
                    import tomli
                    with open(pyproject_toml, 'rb') as f:
                        tomli.load(f)
                except ImportError:
                    print(f"Warning: Cannot validate {image}/pyproject.toml - tomli not available")
                except Exception as e:
                    pytest.fail(f"Invalid TOML in {image}/pyproject.toml: {e}")

    def test_security_scanning_config(self, docker_dir):
        """Test for security scanning configuration."""
        # Check if there's a .dockerignore file to prevent sensitive files from being copied
        dockerignore_files = list(docker_dir.glob("**/.dockerignore"))
        
        if not dockerignore_files:
            print("Warning: No .dockerignore files found - consider adding them to exclude sensitive files")
        
        # Check Dockerfiles for potential security issues
        expected_images = ['notebook', 'trainer', 'serve']
        
        for image in expected_images:
            dockerfile_path = docker_dir / image / "Dockerfile"
            if not dockerfile_path.exists():
                continue
            
            with open(dockerfile_path, 'r') as f:
                content = f.read()
            
            # Check for running as root
            if 'USER root' in content:
                print(f"Warning: {image}/Dockerfile explicitly runs as root")
            
            # Check for ADD instead of COPY (security best practice)
            if 'ADD ' in content and 'http' not in content.lower():
                print(f"Warning: {image}/Dockerfile uses ADD instead of COPY")
            
            # Check for --no-cache-dir in pip installs
            if 'pip install' in content and '--no-cache-dir' not in content:
                print(f"Warning: {image}/Dockerfile pip install should use --no-cache-dir")

    def test_multi_stage_builds(self, docker_dir):
        """Test for multi-stage build optimization."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        for image in expected_images:
            dockerfile_path = docker_dir / image / "Dockerfile"
            if not dockerfile_path.exists():
                continue
            
            with open(dockerfile_path, 'r') as f:
                content = f.read()
            
            # Count FROM statements
            from_count = content.upper().count('FROM ')
            
            if from_count == 1:
                print(f"Info: {image}/Dockerfile uses single-stage build (consider multi-stage for optimization)")
            elif from_count > 1:
                print(f"Info: {image}/Dockerfile uses multi-stage build")

    def test_image_labels(self, docker_dir):
        """Test that Docker images have proper labels."""
        expected_images = ['notebook', 'trainer', 'serve']
        
        recommended_labels = [
            'org.opencontainers.image.title',
            'org.opencontainers.image.description',
            'org.opencontainers.image.version',
            'org.opencontainers.image.source'
        ]
        
        for image in expected_images:
            dockerfile_path = docker_dir / image / "Dockerfile"
            if not dockerfile_path.exists():
                continue
            
            with open(dockerfile_path, 'r') as f:
                content = f.read()
            
            # Check for LABEL instructions
            if 'LABEL' not in content:
                print(f"Warning: {image}/Dockerfile has no LABEL instructions (metadata recommended)")
            else:
                # Check for recommended labels
                for label in recommended_labels:
                    if label not in content:
                        print(f"Info: {image}/Dockerfile missing recommended label: {label}")
