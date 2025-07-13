#!/bin/bash

# DNS Debugging Script for Kubernetes Cross-Namespace Communication
# This script helps diagnose DNS issues between Ray and Grafana services

set -e

echo "=== Kubernetes DNS Debugging ==="
echo "Checking DNS resolution between Ray and Grafana services"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

print_status "1. Checking monitoring namespace services..."
echo "Services in monitoring namespace:"
kubectl get svc -n monitoring -o wide || print_warning "No services found in monitoring namespace"
echo

print_status "2. Looking for Grafana services specifically..."
GRAFANA_SERVICES=$(kubectl get svc -n monitoring -o name | grep -i grafana || true)
if [ -z "$GRAFANA_SERVICES" ]; then
    print_warning "No Grafana services found in monitoring namespace"
else
    print_success "Found Grafana services:"
    for svc in $GRAFANA_SERVICES; do
        SVC_NAME=$(echo $svc | cut -d'/' -f2)
        echo "  - $SVC_NAME"
        kubectl get svc $SVC_NAME -n monitoring -o jsonpath='{.metadata.name}{"\t"}{.spec.clusterIP}{"\t"}{.spec.ports[0].port}{"\n"}' | \
        awk '{printf "    Name: %s, ClusterIP: %s, Port: %s\n", $1, $2, $3}'
    done
fi
echo

print_status "3. Checking default namespace services (where Ray might be)..."
echo "Services in default namespace:"
kubectl get svc -n default -o wide || print_warning "No services found in default namespace"
echo

print_status "4. Looking for Ray services..."
RAY_SERVICES=$(kubectl get svc --all-namespaces -o name | grep -i ray || true)
if [ -z "$RAY_SERVICES" ]; then
    print_warning "No Ray services found in any namespace"
else
    print_success "Found Ray services:"
    kubectl get svc --all-namespaces | grep -i ray || true
fi
echo

print_status "5. Testing DNS resolution from a test pod..."

# Create a temporary test pod for DNS testing
TEST_POD_NAME="dns-test-$(date +%s)"
print_status "Creating test pod: $TEST_POD_NAME"

kubectl run $TEST_POD_NAME --image=busybox --rm -it --restart=Never --command -- sleep 3600 &
sleep 5

# Wait for pod to be ready
print_status "Waiting for test pod to be ready..."
kubectl wait --for=condition=Ready pod/$TEST_POD_NAME --timeout=60s

print_status "6. Testing DNS resolution from test pod..."

# Test basic DNS
print_status "Testing basic DNS resolution..."
kubectl exec $TEST_POD_NAME -- nslookup kubernetes.default.svc.cluster.local || print_warning "Basic DNS test failed"

# Test monitoring namespace DNS
print_status "Testing monitoring namespace DNS..."
kubectl exec $TEST_POD_NAME -- nslookup monitoring.svc.cluster.local || print_warning "Monitoring namespace DNS failed"

# Test specific Grafana service names
if [ ! -z "$GRAFANA_SERVICES" ]; then
    for svc in $GRAFANA_SERVICES; do
        SVC_NAME=$(echo $svc | cut -d'/' -f2)
        print_status "Testing Grafana service: $SVC_NAME.monitoring.svc.cluster.local"
        kubectl exec $TEST_POD_NAME -- nslookup $SVC_NAME.monitoring.svc.cluster.local || print_warning "Failed to resolve $SVC_NAME"
    done
fi

# Test common Grafana service names
print_status "Testing common Grafana service name patterns..."
COMMON_NAMES=(
    "kube-prometheus-stack-grafana"
    "prometheus-grafana" 
    "grafana"
    "monitoring-grafana"
)

for name in "${COMMON_NAMES[@]}"; do
    print_status "Testing: $name.monitoring.svc.cluster.local"
    if kubectl exec $TEST_POD_NAME -- nslookup $name.monitoring.svc.cluster.local 2>/dev/null; then
        print_success "✓ $name.monitoring.svc.cluster.local resolves correctly"
    else
        print_warning "✗ $name.monitoring.svc.cluster.local does not resolve"
    fi
done

print_status "7. Checking CoreDNS configuration..."
kubectl get configmap coredns -n kube-system -o yaml | grep -A 20 "Corefile:" || print_warning "Could not retrieve CoreDNS config"

print_status "8. Checking if CoreDNS pods are running..."
kubectl get pods -n kube-system -l k8s-app=kube-dns || print_warning "CoreDNS pods not found"

# Cleanup
print_status "Cleaning up test pod..."
kubectl delete pod $TEST_POD_NAME --force --grace-period=0 2>/dev/null || true

echo
print_status "=== DNS Debugging Complete ==="
echo
print_status "Summary of findings:"
echo "1. Check the actual Grafana service name from the output above"
echo "2. Use the format: <service-name>.monitoring.svc.cluster.local"
echo "3. Ensure both Ray and Grafana pods can resolve DNS"
echo "4. If DNS resolution fails, check CoreDNS pods and configuration"
echo
print_status "Common Grafana service URLs to try:"
echo "- http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80"
echo "- http://prometheus-grafana.monitoring.svc.cluster.local:80"
echo "- http://grafana.monitoring.svc.cluster.local:80"
