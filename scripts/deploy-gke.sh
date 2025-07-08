#!/bin/bash
# GKE Deployment Script for ML Platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Default values
ENVIRONMENT="dev"
PROJECT_ID=""
REGION="us-central1"
SKIP_TERRAFORM=false
SKIP_APPS=false

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy ML Platform to Google Kubernetes Engine

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -e, --environment ENV           Environment (dev/staging/prod) [default: dev]
    -r, --region REGION             GCP Region [default: us-central1]
    --skip-terraform                Skip Terraform infrastructure deployment
    --skip-apps                     Skip application deployment
    -h, --help                      Show this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --environment prod --region us-west1
    $0 --project-id my-gcp-project --skip-terraform
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-apps)
            SKIP_APPS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id option."
    usage
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform >= 1.0"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install Helm >= 3.0"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Set gcloud project
    gcloud config set project "$PROJECT_ID"
    
    log_info "Prerequisites check passed!"
}

# Enable required GCP APIs
enable_apis() {
    log_info "Enabling required GCP APIs..."
    
    local apis=(
        "container.googleapis.com"
        "compute.googleapis.com"
        "storage.googleapis.com"
        "file.googleapis.com"
        "artifactregistry.googleapis.com"
        "iam.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --project="$PROJECT_ID"
    done
    
    log_info "APIs enabled successfully!"
}

# Deploy Terraform infrastructure
deploy_infrastructure() {
    if [[ "$SKIP_TERRAFORM" == "true" ]]; then
        log_warn "Skipping Terraform deployment"
        return 0
    fi
    
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if terraform.tfvars exists
    if [[ ! -f "terraform.tfvars" ]]; then
        log_error "terraform.tfvars not found. Copy from terraform.tfvars.example and configure."
        exit 1
    fi
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan \
        -var="project_id=$PROJECT_ID" \
        -var="environment=$ENVIRONMENT" \
        -var="region=$REGION"
    
    # Apply deployment
    log_info "Applying Terraform deployment..."
    terraform apply \
        -var="project_id=$PROJECT_ID" \
        -var="environment=$ENVIRONMENT" \
        -var="region=$REGION" \
        -auto-approve
    
    log_info "Infrastructure deployed successfully!"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl..."
    
    cd "$TERRAFORM_DIR"
    
    # Get cluster name from Terraform output
    local cluster_name
    cluster_name=$(terraform output -raw cluster_name)
    
    # Configure kubectl
    gcloud container clusters get-credentials "$cluster_name" \
        --region "$REGION" \
        --project "$PROJECT_ID"
    
    # Verify connection
    kubectl cluster-info
    
    log_info "kubectl configured successfully!"
}

# Deploy applications
deploy_applications() {
    if [[ "$SKIP_APPS" == "true" ]]; then
        log_warn "Skipping application deployment"
        return 0
    fi
    
    log_info "Deploying applications..."
    
    cd "$PROJECT_ROOT"
    
    # Deploy ArgoCD first
    log_info "Deploying ArgoCD..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    
    # Apply ArgoCD applications
    log_info "Applying ArgoCD applications..."
    kubectl apply -f manifests/applications/
    
    log_info "Applications deployed successfully!"
}

# Get access information
get_access_info() {
    log_info "Getting access information..."
    
    cd "$TERRAFORM_DIR"
    
    echo ""
    echo "=== DEPLOYMENT COMPLETE ==="
    echo ""
    echo "Cluster Information:"
    terraform output cluster_name
    terraform output cluster_endpoint
    echo ""
    echo "Storage Information:"
    terraform output gcs_buckets
    echo ""
    echo "Registry Information:"
    terraform output artifact_registry_repositories
    echo ""
    echo "ArgoCD Access:"
    echo "  Port forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Username: admin"
    echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    echo "Next Steps:"
    echo "1. Access ArgoCD UI and sync applications"
    echo "2. Configure monitoring dashboards"
    echo "3. Update CI/CD pipelines with new registry URLs"
    echo ""
}

# Main execution
main() {
    log_info "Starting GKE deployment for ML Platform..."
    log_info "Project: $PROJECT_ID, Environment: $ENVIRONMENT, Region: $REGION"
    
    check_prerequisites
    enable_apis
    deploy_infrastructure
    configure_kubectl
    deploy_applications
    get_access_info
    
    log_info "Deployment completed successfully!"
}

# Run main function
main "$@"
