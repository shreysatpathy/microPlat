#!/bin/bash
# debug-jupyter-ray-connection.sh
# 
# This script diagnoses connectivity issues between JupyterHub notebooks and Ray services.
# It tests DNS resolution, network policy enforcement, and HTTP connectivity.
#
# Usage: ./debug-jupyter-ray-connection.sh [jupyter-pod-name] [ray-service-name]
#
# Example: ./debug-jupyter-ray-connection.sh jupyter-admin ray-sample-cluster-head-svc

set -e

# Default values
JUPYTER_POD=${1:-"jupyter-admin"}
RAY_SERVICE=${2:-"ray-sample-cluster-head-svc"}
RAY_NAMESPACE=${3:-"ml-dev"}
JUPYTER_NAMESPACE=${4:-"ml-dev"}
RAY_PORT=${5:-"8000"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================${NC}"
echo -e "${BLUE}= JupyterHub to Ray Connectivity Diagnostic Tool        =${NC}"
echo -e "${BLUE}=========================================================${NC}"

# Check if pods and services exist
echo -e "\n${YELLOW}[1] Verifying Jupyter pod and Ray service existence...${NC}"

# Check Jupyter pod
if kubectl get pod -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} &>/dev/null; then
    echo -e "${GREEN}✓ Jupyter pod '${JUPYTER_POD}' found in namespace '${JUPYTER_NAMESPACE}'${NC}"
    JUPYTER_POD_STATUS=$(kubectl get pod -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -o jsonpath='{.status.phase}')
    echo -e "  - Pod status: ${JUPYTER_POD_STATUS}"
else
    echo -e "${RED}✗ Jupyter pod '${JUPYTER_POD}' not found in namespace '${JUPYTER_NAMESPACE}'${NC}"
    echo -e "Available pods in ${JUPYTER_NAMESPACE} namespace:"
    kubectl get pods -n ${JUPYTER_NAMESPACE}
    exit 1
fi

# Check Ray service
if kubectl get service -n ${RAY_NAMESPACE} ${RAY_SERVICE} &>/dev/null; then
    echo -e "${GREEN}✓ Ray service '${RAY_SERVICE}' found in namespace '${RAY_NAMESPACE}'${NC}"
    
    # Get service details
    SERVICE_TYPE=$(kubectl get service -n ${RAY_NAMESPACE} ${RAY_SERVICE} -o jsonpath='{.spec.type}')
    SERVICE_CLUSTER_IP=$(kubectl get service -n ${RAY_NAMESPACE} ${RAY_SERVICE} -o jsonpath='{.spec.clusterIP}')
    
    # Check if the port exists
    if kubectl get service -n ${RAY_NAMESPACE} ${RAY_SERVICE} -o jsonpath="{.spec.ports[?(@.port==${RAY_PORT})].port}" &>/dev/null; then
        PORT_DETAILS=$(kubectl get service -n ${RAY_NAMESPACE} ${RAY_SERVICE} -o jsonpath="{.spec.ports[?(@.port==${RAY_PORT})].targetPort}")
        NODE_PORT=$(kubectl get service -n ${RAY_NAMESPACE} ${RAY_SERVICE} -o jsonpath="{.spec.ports[?(@.port==${RAY_PORT})].nodePort}")
        echo -e "  - Service type: ${SERVICE_TYPE}"
        echo -e "  - Cluster IP: ${SERVICE_CLUSTER_IP}"
        echo -e "  - Port ${RAY_PORT} mapped to targetPort: ${PORT_DETAILS}, nodePort: ${NODE_PORT}"
    else
        echo -e "${RED}✗ Port ${RAY_PORT} not found in service '${RAY_SERVICE}'${NC}"
        echo -e "Available ports:"
        kubectl get service -n ${RAY_NAMESPACE} ${RAY_SERVICE} -o jsonpath='{.spec.ports[*].port}'
        echo ""
    fi
else
    echo -e "${RED}✗ Ray service '${RAY_SERVICE}' not found in namespace '${RAY_NAMESPACE}'${NC}"
    echo -e "Available services in ${RAY_NAMESPACE} namespace:"
    kubectl get services -n ${RAY_NAMESPACE}
    exit 1
fi

# Check network policies
echo -e "\n${YELLOW}[2] Checking network policies...${NC}"
echo -e "Network policies in ${JUPYTER_NAMESPACE} namespace:"
kubectl get networkpolicies -n ${JUPYTER_NAMESPACE} -o wide

# Check for jupyterhub-network-policy
JUPYTERHUB_POLICY=$(kubectl get networkpolicies -n ${JUPYTER_NAMESPACE} -o jsonpath='{.items[?(@.metadata.name=="jupyterhub-network-policy")].metadata.name}' 2>/dev/null)
if [ -n "$JUPYTERHUB_POLICY" ]; then
    echo -e "${GREEN}✓ Found JupyterHub network policy: ${JUPYTERHUB_POLICY}${NC}"
    
    # Check if policy allows egress to Ray service
    POLICY_YAML=$(kubectl get networkpolicy -n ${JUPYTER_NAMESPACE} ${JUPYTERHUB_POLICY} -o yaml)
    if echo "$POLICY_YAML" | grep -q "${RAY_NAMESPACE}"; then
        echo -e "${GREEN}✓ Network policy includes rules for ${RAY_NAMESPACE} namespace${NC}"
    else
        echo -e "${RED}✗ Network policy does not explicitly allow access to ${RAY_NAMESPACE} namespace${NC}"
    fi
    
    if echo "$POLICY_YAML" | grep -q "${RAY_PORT}"; then
        echo -e "${GREEN}✓ Network policy includes rules for port ${RAY_PORT}${NC}"
    else
        echo -e "${RED}✗ Network policy does not explicitly allow access to port ${RAY_PORT}${NC}"
    fi
else
    echo -e "${YELLOW}! No specific JupyterHub network policy found named 'jupyterhub-network-policy'${NC}"
    echo -e "  Other network policies might be applying. Checking all policies..."
    
    kubectl get networkpolicies -n ${JUPYTER_NAMESPACE} -o name | sed 's|networkpolicy.networking.k8s.io/||'
fi

# Test DNS resolution
echo -e "\n${YELLOW}[3] Testing DNS resolution from Jupyter pod...${NC}"

# Full service name with namespace
FULL_SERVICE_NAME="${RAY_SERVICE}.${RAY_NAMESPACE}.svc.cluster.local"
SHORT_SERVICE_NAME="${RAY_SERVICE}.${RAY_NAMESPACE}"

echo -e "Testing resolution of: ${FULL_SERVICE_NAME}"
if kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- nslookup ${FULL_SERVICE_NAME} &>/dev/null; then
    echo -e "${GREEN}✓ DNS resolution successful for ${FULL_SERVICE_NAME}${NC}"
    kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- nslookup ${FULL_SERVICE_NAME}
else
    echo -e "${RED}✗ DNS resolution failed for ${FULL_SERVICE_NAME}${NC}"
    echo -e "Trying short name: ${SHORT_SERVICE_NAME}"
    
    if kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- nslookup ${SHORT_SERVICE_NAME} &>/dev/null; then
        echo -e "${GREEN}✓ DNS resolution successful for ${SHORT_SERVICE_NAME}${NC}"
        kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- nslookup ${SHORT_SERVICE_NAME}
    else
        echo -e "${RED}✗ DNS resolution failed for ${SHORT_SERVICE_NAME} as well${NC}"
        
        # Test direct IP resolution
        echo -e "Testing direct IP resolution: ${SERVICE_CLUSTER_IP}"
        kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- nslookup ${SERVICE_CLUSTER_IP}
    fi
fi

# Test network connectivity
echo -e "\n${YELLOW}[4] Testing network connectivity...${NC}"

echo -e "Testing TCP connectivity to ${FULL_SERVICE_NAME}:${RAY_PORT}..."
if kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- timeout 5 bash -c "echo > /dev/tcp/${FULL_SERVICE_NAME}/${RAY_PORT}" &>/dev/null; then
    echo -e "${GREEN}✓ TCP connection successful to ${FULL_SERVICE_NAME}:${RAY_PORT}${NC}"
else
    echo -e "${RED}✗ TCP connection failed to ${FULL_SERVICE_NAME}:${RAY_PORT}${NC}"
    echo -e "Trying direct IP: ${SERVICE_CLUSTER_IP}:${RAY_PORT}..."
    
    if kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- timeout 5 bash -c "echo > /dev/tcp/${SERVICE_CLUSTER_IP}/${RAY_PORT}" &>/dev/null; then
        echo -e "${GREEN}✓ TCP connection successful to ${SERVICE_CLUSTER_IP}:${RAY_PORT}${NC}"
    else
        echo -e "${RED}✗ TCP connection failed to ${SERVICE_CLUSTER_IP}:${RAY_PORT}${NC}"
    fi
fi

# Test HTTP request
echo -e "\n${YELLOW}[5] Testing HTTP requests...${NC}"

echo -e "Attempting HTTP GET request to http://${FULL_SERVICE_NAME}:${RAY_PORT}/"
CURL_OUTPUT=$(kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- curl -s -m 5 -o /dev/null -w "%{http_code}" http://${FULL_SERVICE_NAME}:${RAY_PORT}/ 2>/dev/null)
if [ "$CURL_OUTPUT" != "000" ]; then
    echo -e "${GREEN}✓ HTTP GET request succeeded with status code: ${CURL_OUTPUT}${NC}"
    echo -e "Full response headers:"
    kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- curl -s -I http://${FULL_SERVICE_NAME}:${RAY_PORT}/
else
    echo -e "${RED}✗ HTTP GET request failed or timed out${NC}"
    echo -e "Trying direct IP: http://${SERVICE_CLUSTER_IP}:${RAY_PORT}/"
    
    CURL_OUTPUT_IP=$(kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- curl -s -m 5 -o /dev/null -w "%{http_code}" http://${SERVICE_CLUSTER_IP}:${RAY_PORT}/ 2>/dev/null)
    if [ "$CURL_OUTPUT_IP" != "000" ]; then
        echo -e "${GREEN}✓ HTTP GET request to IP succeeded with status code: ${CURL_OUTPUT_IP}${NC}"
    else
        echo -e "${RED}✗ HTTP GET request to IP failed or timed out${NC}"
    fi
fi

# Check Ray pod logs
echo -e "\n${YELLOW}[6] Checking Ray head pod logs for service on port ${RAY_PORT}...${NC}"
RAY_HEAD_POD=$(kubectl get pods -n ${RAY_NAMESPACE} -l ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')
if [ -n "$RAY_HEAD_POD" ]; then
    echo -e "Ray head pod: ${RAY_HEAD_POD}"
    echo -e "Checking logs for port ${RAY_PORT}:"
    kubectl logs -n ${RAY_NAMESPACE} ${RAY_HEAD_POD} --tail=20 | grep -i "port.*${RAY_PORT}" || echo "No explicit port ${RAY_PORT} mention found in recent logs"
    
    # Check if Ray Serve is running
    echo -e "\nChecking if Ray Serve is running:"
    kubectl exec -n ${RAY_NAMESPACE} ${RAY_HEAD_POD} -- ps aux | grep -i "serve" || echo "No Ray Serve process found"
else
    echo -e "${RED}✗ No Ray head pod found${NC}"
fi

# Check if container on port 8000 is listening
echo -e "\n${YELLOW}[7] Verifying if port ${RAY_PORT} is actually listening in Ray pod...${NC}"
if [ -n "$RAY_HEAD_POD" ]; then
    echo -e "Checking netstat in Ray head pod:"
    kubectl exec -n ${RAY_NAMESPACE} ${RAY_HEAD_POD} -- netstat -tulpn | grep ${RAY_PORT} || echo "Port ${RAY_PORT} does not appear to be listening inside the Ray container"
else
    echo -e "${RED}✗ Cannot check listening ports - no Ray head pod found${NC}"
fi

# Generate test script for Jupyter
echo -e "\n${YELLOW}[8] Creating a test script for Jupyter notebook...${NC}"

TEST_SCRIPT=$(cat <<'EOF'
import requests
import socket
import subprocess
from urllib.parse import urlparse
import time

def test_service_connectivity(service_url, timeout=5):
    """Test connectivity to a service URL"""
    print(f"Testing connectivity to: {service_url}")
    
    # Parse URL
    parsed = urlparse(service_url)
    host = parsed.netloc.split(':')[0]
    port = parsed.port or (443 if parsed.scheme == 'https' else 80)
    
    results = {}
    
    # Test DNS resolution
    try:
        print(f"\n1. Testing DNS resolution for {host}...")
        ip_address = socket.gethostbyname(host)
        print(f"✓ DNS resolution successful: {host} -> {ip_address}")
        results['dns'] = True
    except socket.gaierror as e:
        print(f"✗ DNS resolution failed: {e}")
        results['dns'] = False
    
    # Test TCP connection
    try:
        print(f"\n2. Testing TCP connection to {host}:{port}...")
        start_time = time.time()
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((host, port))
        s.close()
        elapsed = time.time() - start_time
        print(f"✓ TCP connection successful ({elapsed:.2f}s)")
        results['tcp'] = True
    except (socket.timeout, socket.error) as e:
        print(f"✗ TCP connection failed: {e}")
        results['tcp'] = False
    
    # Test HTTP request
    try:
        print(f"\n3. Testing HTTP request to {service_url}...")
        start_time = time.time()
        response = requests.get(service_url, timeout=timeout)
        elapsed = time.time() - start_time
        print(f"✓ HTTP request successful: Status {response.status_code} ({elapsed:.2f}s)")
        print(f"Response headers: {dict(response.headers)}")
        results['http'] = True
        results['status_code'] = response.status_code
        
        # Show preview of response content
        content_preview = response.text[:500] + ('...' if len(response.text) > 500 else '')
        print(f"Response content preview:\n{content_preview}")
    except requests.exceptions.RequestException as e:
        print(f"✗ HTTP request failed: {e}")
        results['http'] = False
    
    return results

# Test Ray service
ray_service = "http://ray-sample-cluster-head-svc.ml-dev.svc.cluster.local:8000"
print(f"=== Testing Ray service at {ray_service} ===")
ray_results = test_service_connectivity(ray_service)

# Test with IP directly
try:
    # Try to get the IP from DNS
    host = urlparse(ray_service).netloc.split(':')[0]
    try:
        ip_address = socket.gethostbyname(host)
        ray_ip_service = f"http://{ip_address}:8000"
        print(f"\n=== Testing Ray service with direct IP at {ray_ip_service} ===")
        ray_ip_results = test_service_connectivity(ray_ip_service)
    except socket.gaierror:
        print("Could not resolve DNS to get IP address for direct testing")
except Exception as e:
    print(f"Error setting up direct IP test: {e}")

# Run a system ping test
try:
    print("\n=== Running system ping test ===")
    ping_host = host
    result = subprocess.run(['ping', '-c', '3', ping_host], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print(result.stdout.decode())
except Exception as e:
    print(f"Error running ping: {e}")
EOF
)

echo -e "Creating test script in Jupyter pod..."
echo "$TEST_SCRIPT" > /tmp/test_ray_connectivity.py
kubectl cp /tmp/test_ray_connectivity.py ${JUPYTER_NAMESPACE}/${JUPYTER_POD}:/tmp/test_ray_connectivity.py

echo -e "${GREEN}✓ Created test script in Jupyter pod at /tmp/test_ray_connectivity.py${NC}"
echo -e "To run the test script from inside the Jupyter notebook, execute:"
echo -e "${BLUE}%run /tmp/test_ray_connectivity.py${NC}"

# Summary
echo -e "\n${YELLOW}[9] Summary and recommendations:${NC}"
echo -e "1. Check if Ray is actually serving anything on port ${RAY_PORT} (Ray Serve application)"
echo -e "2. Verify that network policies are correctly configured"
echo -e "3. Check if Jupyter pod has the necessary permissions to access Ray service"
echo -e "4. Verify that the service and port are correctly defined in Ray configuration"

echo -e "\n${YELLOW}Additional commands for debugging:${NC}"
echo -e "${BLUE}# Run the test script in Jupyter${NC}"
echo -e "kubectl exec -n ${JUPYTER_NAMESPACE} ${JUPYTER_POD} -- python /tmp/test_ray_connectivity.py"
echo -e "\n${BLUE}# Check if Ray Serve is installed${NC}"
echo -e "kubectl exec -n ${RAY_NAMESPACE} ${RAY_HEAD_POD} -- pip list | grep ray"
echo -e "\n${BLUE}# Check Ray container environment${NC}"
echo -e "kubectl exec -n ${RAY_NAMESPACE} ${RAY_HEAD_POD} -- env | grep -i ray"

echo -e "\n${BLUE}=========================================================${NC}"
echo -e "${BLUE}= Debugging complete                                     =${NC}"
echo -e "${BLUE}=========================================================${NC}"
