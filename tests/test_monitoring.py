#!/usr/bin/env python3
"""
Test suite for monitoring stack validation
"""

import pytest
import requests
import time
import subprocess
import json
from typing import Dict, List, Optional


class TestMonitoringStack:
    """Test cases for kube-prometheus-stack monitoring"""
    
    @pytest.fixture(scope="class")
    def monitoring_namespace(self) -> str:
        """Return the monitoring namespace"""
        return "monitoring"
    
    @pytest.fixture(scope="class")
    def kubectl_context(self) -> Optional[str]:
        """Get current kubectl context"""
        try:
            result = subprocess.run(
                ["kubectl", "config", "current-context"],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None
    
    def test_monitoring_namespace_exists(self, monitoring_namespace: str):
        """Test that monitoring namespace exists"""
        result = subprocess.run(
            ["kubectl", "get", "namespace", monitoring_namespace],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Monitoring namespace {monitoring_namespace} does not exist"
    
    def test_prometheus_deployment(self, monitoring_namespace: str):
        """Test Prometheus deployment status"""
        result = subprocess.run([
            "kubectl", "get", "statefulset", 
            "-n", monitoring_namespace,
            "-l", "app.kubernetes.io/name=prometheus",
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get Prometheus statefulset"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No Prometheus statefulset found"
        
        prometheus_sts = data["items"][0]
        assert prometheus_sts["status"]["readyReplicas"] == prometheus_sts["status"]["replicas"], \
            "Prometheus statefulset not ready"
    
    def test_grafana_deployment(self, monitoring_namespace: str):
        """Test Grafana deployment status"""
        result = subprocess.run([
            "kubectl", "get", "deployment",
            "-n", monitoring_namespace,
            "-l", "app.kubernetes.io/name=grafana",
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get Grafana deployment"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No Grafana deployment found"
        
        grafana_deploy = data["items"][0]
        assert grafana_deploy["status"]["readyReplicas"] == grafana_deploy["status"]["replicas"], \
            "Grafana deployment not ready"
    
    def test_alertmanager_deployment(self, monitoring_namespace: str):
        """Test Alertmanager deployment status"""
        result = subprocess.run([
            "kubectl", "get", "statefulset",
            "-n", monitoring_namespace,
            "-l", "app.kubernetes.io/name=alertmanager",
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get Alertmanager statefulset"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No Alertmanager statefulset found"
        
        alertmanager_sts = data["items"][0]
        assert alertmanager_sts["status"]["readyReplicas"] == alertmanager_sts["status"]["replicas"], \
            "Alertmanager statefulset not ready"
    
    def test_prometheus_operator_deployment(self, monitoring_namespace: str):
        """Test Prometheus Operator deployment status"""
        result = subprocess.run([
            "kubectl", "get", "deployment",
            "-n", monitoring_namespace,
            "-l", "app.kubernetes.io/name=kube-prometheus-stack-operator",
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get Prometheus Operator deployment"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No Prometheus Operator deployment found"
        
        operator_deploy = data["items"][0]
        assert operator_deploy["status"]["readyReplicas"] == operator_deploy["status"]["replicas"], \
            "Prometheus Operator deployment not ready"
    
    def test_node_exporter_daemonset(self, monitoring_namespace: str):
        """Test Node Exporter DaemonSet status"""
        result = subprocess.run([
            "kubectl", "get", "daemonset",
            "-n", monitoring_namespace,
            "-l", "app.kubernetes.io/name=node-exporter",
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get Node Exporter daemonset"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No Node Exporter daemonset found"
        
        node_exporter_ds = data["items"][0]
        assert node_exporter_ds["status"]["numberReady"] == node_exporter_ds["status"]["desiredNumberScheduled"], \
            "Node Exporter daemonset not ready"
    
    def test_kube_state_metrics_deployment(self, monitoring_namespace: str):
        """Test kube-state-metrics deployment status"""
        result = subprocess.run([
            "kubectl", "get", "deployment",
            "-n", monitoring_namespace,
            "-l", "app.kubernetes.io/name=kube-state-metrics",
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get kube-state-metrics deployment"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No kube-state-metrics deployment found"
        
        ksm_deploy = data["items"][0]
        assert ksm_deploy["status"]["readyReplicas"] == ksm_deploy["status"]["replicas"], \
            "kube-state-metrics deployment not ready"
    
    def test_prometheus_rules_created(self, monitoring_namespace: str):
        """Test that custom PrometheusRule resources are created"""
        result = subprocess.run([
            "kubectl", "get", "prometheusrule",
            "-n", monitoring_namespace,
            "-l", "prometheus=kube-prometheus",
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get PrometheusRule resources"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No PrometheusRule resources found"
        
        # Check for ML platform specific rules
        ml_rules_found = False
        for rule in data["items"]:
            if "ml-platform" in rule["metadata"]["name"]:
                ml_rules_found = True
                break
        
        assert ml_rules_found, "ML platform specific PrometheusRule not found"
    
    def test_service_monitors_created(self, monitoring_namespace: str):
        """Test that ServiceMonitor resources are created"""
        result = subprocess.run([
            "kubectl", "get", "servicemonitor",
            "-n", monitoring_namespace,
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get ServiceMonitor resources"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No ServiceMonitor resources found"
    
    def test_persistent_volumes_bound(self, monitoring_namespace: str):
        """Test that PVCs are bound for persistent storage"""
        result = subprocess.run([
            "kubectl", "get", "pvc",
            "-n", monitoring_namespace,
            "-o", "json"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, "Failed to get PVC resources"
        
        data = json.loads(result.stdout)
        assert len(data["items"]) > 0, "No PVC resources found"
        
        for pvc in data["items"]:
            assert pvc["status"]["phase"] == "Bound", \
                f"PVC {pvc['metadata']['name']} is not bound"
    
    @pytest.mark.integration
    def test_prometheus_api_accessible(self, monitoring_namespace: str):
        """Test Prometheus API accessibility via port-forward"""
        # Start port-forward in background
        port_forward_proc = subprocess.Popen([
            "kubectl", "port-forward",
            "-n", monitoring_namespace,
            "svc/prometheus-stack-kube-prom-prometheus",
            "9090:9090"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        try:
            # Wait for port-forward to establish
            time.sleep(5)
            
            # Test API endpoint
            response = requests.get("http://localhost:9090/api/v1/status/config", timeout=10)
            assert response.status_code == 200, "Prometheus API not accessible"
            
            # Test targets endpoint
            response = requests.get("http://localhost:9090/api/v1/targets", timeout=10)
            assert response.status_code == 200, "Prometheus targets endpoint not accessible"
            
        finally:
            port_forward_proc.terminate()
            port_forward_proc.wait()
    
    @pytest.mark.integration
    def test_grafana_api_accessible(self, monitoring_namespace: str):
        """Test Grafana API accessibility via port-forward"""
        # Start port-forward in background
        port_forward_proc = subprocess.Popen([
            "kubectl", "port-forward",
            "-n", monitoring_namespace,
            "svc/prometheus-stack-grafana",
            "3000:80"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        try:
            # Wait for port-forward to establish
            time.sleep(5)
            
            # Test health endpoint
            response = requests.get("http://localhost:3000/api/health", timeout=10)
            assert response.status_code == 200, "Grafana API not accessible"
            
        finally:
            port_forward_proc.terminate()
            port_forward_proc.wait()
    
    def test_ray_cluster_monitoring_config(self):
        """Test Ray cluster monitoring configuration"""
        # Check if Ray cluster values include monitoring annotations
        with open("charts/ray-cluster/values.yaml", "r") as f:
            content = f.read()
            
        assert "prometheus.io/scrape" in content, "Ray cluster missing Prometheus scrape annotation"
        assert "prometheus.io/port" in content, "Ray cluster missing Prometheus port annotation"
        assert "metrics-export-port: 8080" in content, "Ray cluster missing metrics export port"


class TestMonitoringIntegration:
    """Integration tests for monitoring with ML platform components"""
    
    def test_ray_metrics_collection(self):
        """Test that Ray metrics are being collected"""
        # This would require a running Ray cluster
        # Implementation depends on your specific Ray deployment
        pass
    
    def test_mlflow_metrics_collection(self):
        """Test that MLflow metrics are being collected"""
        # This would require a running MLflow instance
        # Implementation depends on your specific MLflow deployment
        pass
    
    def test_jupyterhub_metrics_collection(self):
        """Test that JupyterHub metrics are being collected"""
        # This would require a running JupyterHub instance
        # Implementation depends on your specific JupyterHub deployment
        pass


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
