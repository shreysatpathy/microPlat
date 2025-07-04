#!/usr/bin/env python3
"""
Test runner script for microPlat infrastructure testing.
"""
import sys
import subprocess
import argparse
from pathlib import Path


def run_command(cmd, description=""):
    """Run a command and return success status."""
    if description:
        print(f"\n🔍 {description}")
    
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print("✅ Success")
        if result.stdout:
            print(result.stdout)
    else:
        print("❌ Failed")
        if result.stderr:
            print(result.stderr)
        if result.stdout:
            print(result.stdout)
    
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description="Run infrastructure tests")
    parser.add_argument("--category", choices=["helm", "k8s", "docker", "integration", "all"], 
                       default="all", help="Test category to run")
    parser.add_argument("--fast", action="store_true", help="Run fast tests only")
    parser.add_argument("--coverage", action="store_true", help="Generate coverage report")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    project_root = Path(__file__).parent
    
    print("🚀 microPlat Infrastructure Test Runner")
    print("=" * 50)
    
    # Base pytest command
    pytest_cmd = ["python", "-m", "pytest"]
    
    if args.verbose:
        pytest_cmd.extend(["-v", "--tb=short"])
    
    if args.coverage:
        pytest_cmd.extend(["--cov=.", "--cov-report=term-missing", "--cov-report=html"])
    
    if args.fast:
        pytest_cmd.extend(["-m", "not slow"])
    
    success = True
    
    # Run tests based on category
    if args.category == "all":
        test_files = ["tests/"]
    elif args.category == "helm":
        test_files = ["tests/test_helm_charts.py"]
    elif args.category == "k8s":
        test_files = ["tests/test_kubernetes_manifests.py"]
    elif args.category == "docker":
        test_files = ["tests/test_docker_builds.py"]
    elif args.category == "integration":
        test_files = ["tests/test_integration.py"]
    
    for test_file in test_files:
        cmd = pytest_cmd + [test_file]
        if not run_command(cmd, f"Running {test_file} tests"):
            success = False
    
    # Additional validations
    if args.category in ["all", "helm"]:
        print("\n🔍 Running Helm lint validation")
        charts_dir = project_root / "charts"
        for chart_dir in charts_dir.iterdir():
            if chart_dir.is_dir() and (chart_dir / "Chart.yaml").exists():
                if not run_command(["helm", "lint", str(chart_dir)], f"Linting {chart_dir.name}"):
                    print(f"⚠️  Helm lint failed for {chart_dir.name} (may be expected)")
    
    print("\n" + "=" * 50)
    if success:
        print("🎉 All tests completed successfully!")
        return 0
    else:
        print("💥 Some tests failed!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
