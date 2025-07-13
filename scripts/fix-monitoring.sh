#!/bin/bash

# Fix Monitoring Stack Issues
# This script diagnoses and fixes common kube-prometheus-stack issues

set -e

NAMESPACE="monitoring"
RELEASE_NAME="kube-prometheus-stack"

echo "🔍 Diagnosing monitoring stack issues..."

# Function to check pod status
check_pod_status() {
    echo "📊 Checking pod status in namespace: $NAMESPACE"
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
}

# Function to check pod logs
check_pod_logs() {
    local pod_name=$1
    echo "📋 Checking logs for pod: $pod_name"
    kubectl logs -n $NAMESPACE $pod_name --tail=50 || echo "Could not retrieve logs for $pod_name"
    echo ""
}

# Function to describe problematic pods
describe_pods() {
    echo "🔍 Describing pods with issues..."
    local problematic_pods=$(kubectl get pods -n $NAMESPACE --no-headers | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff|Pending)" | awk '{print $1}' || true)
    
    if [ -n "$problematic_pods" ]; then
        for pod in $problematic_pods; do
            echo "Describing pod: $pod"
            kubectl describe pod $pod -n $NAMESPACE
            echo "---"
        done
    else
        echo "No pods with obvious issues found"
    fi
}

# Function to check services and endpoints
check_services() {
    echo "🌐 Checking services and endpoints..."
    kubectl get svc -n $NAMESPACE
    echo ""
    kubectl get endpoints -n $NAMESPACE
    echo ""
}

# Function to check persistent volumes
check_storage() {
    echo "💾 Checking persistent volumes and claims..."
    kubectl get pvc -n $NAMESPACE
    echo ""
    kubectl get pv | grep $NAMESPACE || echo "No PVs found for monitoring namespace"
    echo ""
}

# Function to restart problematic pods
restart_pods() {
    echo "🔄 Restarting monitoring stack components..."
    
    # Restart Grafana deployment
    kubectl rollout restart deployment/$RELEASE_NAME-grafana -n $NAMESPACE
    echo "Restarted Grafana deployment"
    
    # Restart Prometheus StatefulSet
    kubectl rollout restart statefulset/prometheus-$RELEASE_NAME-prometheus -n $NAMESPACE
    echo "Restarted Prometheus StatefulSet"
    
    # Restart Alertmanager StatefulSet
    kubectl rollout restart statefulset/alertmanager-$RELEASE_NAME-alertmanager -n $NAMESPACE
    echo "Restarted Alertmanager StatefulSet"
    
    echo "Waiting for rollouts to complete..."
    kubectl rollout status deployment/$RELEASE_NAME-grafana -n $NAMESPACE --timeout=300s
    kubectl rollout status statefulset/prometheus-$RELEASE_NAME-prometheus -n $NAMESPACE --timeout=300s
    kubectl rollout status statefulset/alertmanager-$RELEASE_NAME-alertmanager -n $NAMESPACE --timeout=300s
}

# Function to check health endpoints
check_health_endpoints() {
    echo "🏥 Checking health endpoints..."
    
    # Get Grafana pod
    local grafana_pod=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=grafana --no-headers | awk '{print $1}' | head -1)
    if [ -n "$grafana_pod" ]; then
        echo "Testing Grafana health endpoint..."
        kubectl exec -n $NAMESPACE $grafana_pod -c grafana -- curl -s http://localhost:3000/api/health || echo "Grafana health check failed"
    fi
    
    # Get Prometheus pod (try different label selectors)
    local prometheus_pod=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=prometheus --no-headers | awk '{print $1}' | head -1)
    if [ -z "$prometheus_pod" ]; then
        prometheus_pod=$(kubectl get pods -n $NAMESPACE -l prometheus=kube-prometheus-stack-prometheus --no-headers | awk '{print $1}' | head -1)
    fi
    if [ -n "$prometheus_pod" ]; then
        echo "Testing Prometheus health endpoint..."
        kubectl exec -n $NAMESPACE $prometheus_pod -c prometheus -- wget -q -O- http://localhost:9090/-/healthy 2>/dev/null || echo "Prometheus health check failed"
    else
        echo "Prometheus pod not found - checking if StatefulSet exists..."
        kubectl get statefulset -n $NAMESPACE | grep prometheus || echo "Prometheus StatefulSet not found"
    fi
    
    # Get Alertmanager pod
    local alertmanager_pod=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=alertmanager --no-headers | awk '{print $1}' | head -1)
    if [ -n "$alertmanager_pod" ]; then
        echo "Testing Alertmanager health endpoint..."
        # Use wget instead of curl as it's more commonly available
        kubectl exec -n $NAMESPACE $alertmanager_pod -c alertmanager -- wget -q -O- http://localhost:9093/-/healthy 2>/dev/null || \
        kubectl exec -n $NAMESPACE $alertmanager_pod -c alertmanager -- sh -c 'echo "GET /-/healthy HTTP/1.1\r\nHost: localhost:9093\r\n\r\n" | nc localhost 9093' 2>/dev/null || \
        echo "Alertmanager health check failed (no wget/nc available)"
    fi
}

# Function to upgrade the monitoring stack
upgrade_monitoring() {
    echo "⬆️ Upgrading monitoring stack with fixed configuration..."
    
    # Check if helm release exists
    if helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
        echo "Upgrading existing release..."
        helm upgrade $RELEASE_NAME ./charts/kube-prometheus-stack -n $NAMESPACE --wait --timeout=10m
    else
        echo "Installing new release..."
        helm install $RELEASE_NAME ./charts/kube-prometheus-stack -n $NAMESPACE --create-namespace --wait --timeout=10m
    fi
}

# Function to setup port forwarding for debugging
setup_port_forwarding() {
    echo "🔗 Setting up port forwarding for debugging..."
    
    # Kill any existing port forwards
    pkill -f "kubectl.*port-forward.*monitoring" || true
    sleep 2
    
    # Setup port forwards in background
    kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-grafana 3000:80 &
    kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-prometheus 9090:9090 &
    kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-alertmanager 9093:9093 &
    
    echo "Port forwarding setup:"
    echo "  Grafana: http://localhost:3000 (admin/admin)"
    echo "  Prometheus: http://localhost:9090"
    echo "  Alertmanager: http://localhost:9093"
    echo ""
    echo "To stop port forwarding: pkill -f 'kubectl.*port-forward.*monitoring'"
}

# Function to check and fix missing Prometheus
check_prometheus_deployment() {
    echo "🔍 Checking Prometheus deployment..."
    
    # Check if Prometheus StatefulSet exists
    local prometheus_sts=$(kubectl get statefulset -n $NAMESPACE -o name | grep prometheus || true)
    if [ -z "$prometheus_sts" ]; then
        echo "❌ Prometheus StatefulSet not found!"
        echo "🔧 This might be due to incomplete deployment. Checking Prometheus Operator..."
        
        # Check Prometheus Operator
        local operator_pod=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=prometheus-operator --no-headers | awk '{print $1}' | head -1)
        if [ -n "$operator_pod" ]; then
            echo "✅ Prometheus Operator is running: $operator_pod"
            echo "📋 Checking Operator logs for errors..."
            kubectl logs -n $NAMESPACE $operator_pod --tail=20 | grep -i error || echo "No obvious errors in operator logs"
        else
            echo "❌ Prometheus Operator not found!"
        fi
        
        # Check for Prometheus CRD
        echo "🔍 Checking for Prometheus custom resource..."
        kubectl get prometheus -n $NAMESPACE || echo "No Prometheus custom resource found"
        
        return 1
    else
        echo "✅ Prometheus StatefulSet found: $prometheus_sts"
        kubectl get $prometheus_sts -n $NAMESPACE
        return 0
    fi
}

# Function to fix missing Prometheus
fix_prometheus_deployment() {
    echo "🛠️ Attempting to fix Prometheus deployment..."
    
    # Check if Prometheus custom resource exists
    if ! kubectl get prometheus -n $NAMESPACE >/dev/null 2>&1; then
        echo "Creating Prometheus custom resource..."
        cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: kube-prometheus-stack-prometheus
  namespace: monitoring
spec:
  serviceAccountName: kube-prometheus-stack-prometheus
  serviceMonitorSelector:
    matchLabels:
      release: kube-prometheus-stack
  ruleSelector:
    matchLabels:
      release: kube-prometheus-stack
  retention: 30d
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: standard
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
EOF
    fi
    
    # Wait for StatefulSet to be created
    echo "Waiting for Prometheus StatefulSet to be created..."
    for i in {1..30}; do
        if kubectl get statefulset -n $NAMESPACE | grep -q prometheus; then
            echo "✅ Prometheus StatefulSet created!"
            break
        fi
        echo "Waiting... ($i/30)"
        sleep 10
    done
}

# Main execution
main() {
    case "${1:-check}" in
        "check")
            echo "🔍 Running comprehensive monitoring stack check..."
            check_pod_status
            describe_pods
            check_services
            check_storage
            check_health_endpoints
            check_prometheus_deployment
            ;;
        "restart")
            echo "🔄 Restarting monitoring stack..."
            restart_pods
            sleep 30
            check_pod_status
            ;;
        "upgrade")
            echo "⬆️ Upgrading monitoring stack..."
            upgrade_monitoring
            check_pod_status
            ;;
        "logs")
            echo "📋 Collecting logs from all monitoring pods..."
            for pod in $(kubectl get pods -n $NAMESPACE --no-headers | awk '{print $1}'); do
                check_pod_logs $pod
            done
            ;;
        "port-forward")
            setup_port_forwarding
            ;;
        "fix")
            echo "🛠️ Running comprehensive fix..."
            check_pod_status
            upgrade_monitoring
            sleep 30
            restart_pods
            sleep 30
            check_pod_status
            check_health_endpoints
            setup_port_forwarding
            check_prometheus_deployment || fix_prometheus_deployment
            ;;
        *)
            echo "Usage: $0 {check|restart|upgrade|logs|port-forward|fix}"
            echo ""
            echo "Commands:"
            echo "  check        - Check status of monitoring stack"
            echo "  restart      - Restart all monitoring components"
            echo "  upgrade      - Upgrade monitoring stack with latest config"
            echo "  logs         - Collect logs from all pods"
            echo "  port-forward - Setup port forwarding for debugging"
            echo "  fix          - Run comprehensive fix (upgrade + restart + check)"
            exit 1
            ;;
    esac
}

main "$@"
