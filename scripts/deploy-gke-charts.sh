#!/bin/bash

# Deploy GKE-optimized Helm charts for ML Platform
# This script deploys the ML platform components to GKE using the optimized charts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${PROJECT_ID:-}"
CLUSTER_NAME="${CLUSTER_NAME:-ml-platform-cluster}"
REGION="${REGION:-us-central1}"
CHARTS_DIR="$(dirname "$0")/../gkeCharts"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if required tools are installed
    local tools=("kubectl" "helm" "gcloud")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check if PROJECT_ID is set
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "PROJECT_ID environment variable is not set"
        print_status "Please set PROJECT_ID: export PROJECT_ID=your-gcp-project-id"
        exit 1
    fi
    
    # Check if connected to the right cluster
    local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    if [[ "$current_context" != *"$CLUSTER_NAME"* ]]; then
        print_warning "Current kubectl context: $current_context"
        print_status "Connecting to GKE cluster..."
        gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"
    fi
    
    print_success "Prerequisites check completed"
}

# Function to update chart values with project-specific information
update_chart_values() {
    print_status "Updating chart values with project-specific information..."
    
    # Get Filestore IP from Terraform output
    local filestore_ip
    if command -v terraform &> /dev/null && [[ -f "../terraform/terraform.tfstate" ]]; then
        filestore_ip=$(cd ../terraform && terraform output -raw filestore_ip 2>/dev/null || echo "")
    fi
    
    if [[ -z "$filestore_ip" ]]; then
        print_warning "Could not get Filestore IP from Terraform output"
        print_status "Please manually update FILESTORE_IP in shared-storage/filestore-pv.yaml"
        filestore_ip="FILESTORE_IP_PLACEHOLDER"
    fi
    
    # Update PROJECT_ID and FILESTORE_IP in all relevant files
    find "$CHARTS_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i.bak "s/PROJECT_ID/$PROJECT_ID/g" {} \;
    find "$CHARTS_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i.bak "s/FILESTORE_IP/$filestore_ip/g" {} \;
    
    # Clean up backup files
    find "$CHARTS_DIR" -name "*.bak" -delete
    
    print_success "Chart values updated"
}

# Function to add Helm repositories
add_helm_repos() {
    print_status "Adding Helm repositories..."
    
    helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo add kuberay https://ray-project.github.io/kuberay-helm/ || true
    helm repo update
    
    print_success "Helm repositories added and updated"
}

# Function to create namespaces
create_namespaces() {
    print_status "Creating Kubernetes namespaces..."
    
    local namespaces=("jupyterhub" "ray-system" "mlflow" "monitoring" "argocd")
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            print_status "Namespace $ns already exists"
        else
            kubectl create namespace "$ns"
            print_success "Created namespace: $ns"
        fi
    done
}

# Function to deploy shared storage
deploy_shared_storage() {
    print_status "Deploying shared storage components..."
    
    # Apply Filestore PV and PVC
    kubectl apply -f "$CHARTS_DIR/shared-storage/filestore-pv.yaml"
    kubectl apply -f "$CHARTS_DIR/shared-storage/filestore-pvc.yaml"
    
    # Apply service accounts with Workload Identity
    kubectl apply -f "$CHARTS_DIR/shared-storage/service-accounts.yaml"
    
    # Wait for PVC to be bound
    print_status "Waiting for Filestore PVC to be bound..."
    kubectl wait --for=condition=Bound pvc/filestore-pvc --timeout=300s || {
        print_warning "PVC binding timeout - continuing anyway"
    }
    
    print_success "Shared storage deployed"
}

# Function to deploy monitoring stack
deploy_monitoring() {
    print_status "Deploying monitoring stack (Prometheus + Grafana)..."
    
    helm upgrade --install monitoring "$CHARTS_DIR/monitoring" \
        --namespace monitoring \
        --create-namespace \
        --wait \
        --timeout=10m
    
    print_success "Monitoring stack deployed"
    
    # Print access information
    print_status "Monitoring access information:"
    echo "  Grafana: kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
    echo "  Prometheus: kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring"
    echo "  Default Grafana credentials: admin/admin123"
}

# Function to deploy MLflow
deploy_mlflow() {
    print_status "Deploying MLflow tracking server..."
    
    helm upgrade --install mlflow "$CHARTS_DIR/mlflow" \
        --namespace mlflow \
        --create-namespace \
        --wait \
        --timeout=10m
    
    print_success "MLflow deployed"
    
    # Print access information
    print_status "MLflow access information:"
    echo "  MLflow UI: kubectl port-forward svc/mlflow 5000:5000 -n mlflow"
    echo "  MLflow URI: http://mlflow.mlflow:5000 (internal)"
}

# Function to deploy Ray cluster
deploy_ray_cluster() {
    print_status "Deploying Ray cluster..."
    
    helm upgrade --install ray-cluster "$CHARTS_DIR/ray-cluster" \
        --namespace ray-system \
        --create-namespace \
        --wait \
        --timeout=15m
    
    print_success "Ray cluster deployed"
    
    # Print access information
    print_status "Ray cluster access information:"
    echo "  Ray Dashboard: kubectl port-forward svc/ray-cluster-head 8265:8265 -n ray-system"
    echo "  Ray Client: ray://ray-head.ray-system:10001"
}

# Function to deploy JupyterHub
deploy_jupyterhub() {
    print_status "Deploying JupyterHub..."
    
    # Generate random token for proxy if not set
    local secret_token=$(openssl rand -hex 32)
    
    helm upgrade --install jupyterhub "$CHARTS_DIR/jupyterhub" \
        --namespace jupyterhub \
        --create-namespace \
        --set jupyterhub.proxy.secretToken="$secret_token" \
        --wait \
        --timeout=15m
    
    print_success "JupyterHub deployed"
    
    # Print access information
    print_status "JupyterHub access information:"
    echo "  JupyterHub: kubectl port-forward svc/proxy-public 8080:80 -n jupyterhub"
    echo "  Default credentials: any username / password: mlplatform"
}

# Function to verify deployments
verify_deployments() {
    print_status "Verifying deployments..."
    
    local namespaces=("monitoring" "mlflow" "ray-system" "jupyterhub")
    
    for ns in "${namespaces[@]}"; do
        print_status "Checking pods in namespace: $ns"
        kubectl get pods -n "$ns"
        
        # Check if all pods are running
        local not_running=$(kubectl get pods -n "$ns" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
        if [[ "$not_running" -gt 0 ]]; then
            print_warning "Some pods in namespace $ns are not running"
        else
            print_success "All pods in namespace $ns are running"
        fi
    done
    
    # Check services
    print_status "Checking services..."
    kubectl get svc -A | grep -E "(mlflow|ray|jupyterhub|monitoring)"
    
    print_success "Deployment verification completed"
}

# Function to print next steps
print_next_steps() {
    print_success "ML Platform deployment completed!"
    echo
    print_status "Next steps:"
    echo "1. Access the applications using the port-forward commands above"
    echo "2. Configure ingress for external access (optional)"
    echo "3. Set up CI/CD pipelines to push images to Artifact Registry"
    echo "4. Migrate data from your existing platform"
    echo "5. Update DNS records if using custom domains"
    echo
    print_status "Useful commands:"
    echo "  # Check all pods"
    echo "  kubectl get pods -A"
    echo
    echo "  # Check persistent volumes"
    echo "  kubectl get pv,pvc -A"
    echo
    echo "  # Access Grafana dashboard"
    echo "  kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
    echo
    echo "  # Access JupyterHub"
    echo "  kubectl port-forward svc/proxy-public 8080:80 -n jupyterhub"
    echo
    echo "  # Check Ray cluster status"
    echo "  kubectl port-forward svc/ray-cluster-head 8265:8265 -n ray-system"
    echo
    print_status "For troubleshooting, check the README.md in the gkeCharts directory"
}

# Main deployment function
main() {
    print_status "Starting ML Platform deployment to GKE..."
    echo "Project ID: $PROJECT_ID"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $REGION"
    echo
    
    # Run deployment steps
    check_prerequisites
    update_chart_values
    add_helm_repos
    create_namespaces
    deploy_shared_storage
    
    # Deploy components in order
    deploy_monitoring
    sleep 30  # Wait for monitoring to stabilize
    
    deploy_mlflow
    sleep 30  # Wait for MLflow to stabilize
    
    deploy_ray_cluster
    sleep 30  # Wait for Ray to stabilize
    
    deploy_jupyterhub
    
    # Verify and provide next steps
    verify_deployments
    print_next_steps
}

# Handle script arguments
case "${1:-}" in
    "monitoring")
        check_prerequisites
        update_chart_values
        add_helm_repos
        create_namespaces
        deploy_monitoring
        ;;
    "mlflow")
        check_prerequisites
        update_chart_values
        create_namespaces
        deploy_mlflow
        ;;
    "ray")
        check_prerequisites
        update_chart_values
        create_namespaces
        deploy_ray_cluster
        ;;
    "jupyterhub")
        check_prerequisites
        update_chart_values
        create_namespaces
        deploy_jupyterhub
        ;;
    "storage")
        check_prerequisites
        update_chart_values
        create_namespaces
        deploy_shared_storage
        ;;
    "verify")
        verify_deployments
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [component]"
        echo
        echo "Deploy ML Platform components to GKE:"
        echo "  $0              # Deploy all components"
        echo "  $0 monitoring   # Deploy only monitoring stack"
        echo "  $0 mlflow       # Deploy only MLflow"
        echo "  $0 ray          # Deploy only Ray cluster"
        echo "  $0 jupyterhub   # Deploy only JupyterHub"
        echo "  $0 storage      # Deploy only shared storage"
        echo "  $0 verify       # Verify existing deployments"
        echo "  $0 help         # Show this help"
        echo
        echo "Environment variables:"
        echo "  PROJECT_ID      # GCP project ID (required)"
        echo "  CLUSTER_NAME    # GKE cluster name (default: ml-platform-cluster)"
        echo "  REGION          # GCP region (default: us-central1)"
        ;;
    *)
        main
        ;;
esac
