"""
Pytest configuration and fixtures for infrastructure testing.
"""
import os
import pytest
import yaml
import subprocess
from pathlib import Path
from typing import Dict, Any, List


@pytest.fixture(scope="session")
def project_root():
    """Get the project root directory."""
    return Path(__file__).parent.parent


@pytest.fixture(scope="session")
def charts_dir(project_root):
    """Get the charts directory."""
    return project_root / "charts"


@pytest.fixture(scope="session")
def manifests_dir(project_root):
    """Get the manifests directory."""
    return project_root / "manifests"


@pytest.fixture(scope="session")
def docker_dir(project_root):
    """Get the docker directory."""
    return project_root / "docker"


@pytest.fixture
def helm_charts(charts_dir):
    """Get list of all Helm charts."""
    charts = []
    for chart_dir in charts_dir.iterdir():
        if chart_dir.is_dir() and (chart_dir / "Chart.yaml").exists():
            charts.append(chart_dir)
    return charts


@pytest.fixture
def kubernetes_manifests(manifests_dir):
    """Get list of all Kubernetes manifest files."""
    manifests = []
    for root, dirs, files in os.walk(manifests_dir):
        for file in files:
            if file.endswith(('.yaml', '.yml')):
                manifests.append(Path(root) / file)
    return manifests


def load_yaml_file(file_path: Path) -> Dict[Any, Any]:
    """Load and parse a YAML file."""
    with open(file_path, 'r') as f:
        return yaml.safe_load(f)


def load_yaml_documents(file_path: Path) -> List[Dict[Any, Any]]:
    """Load multiple YAML documents from a file."""
    with open(file_path, 'r') as f:
        return list(yaml.safe_load_all(f))


def run_command(cmd: List[str], cwd: Path = None) -> subprocess.CompletedProcess:
    """Run a shell command and return the result."""
    return subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False
    )
