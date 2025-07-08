#!/bin/bash

# Data Migration Script: Minikube to GKE
# This script helps migrate data from minikube-based ML platform to GKE

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="./migration-backup"
MINIKUBE_CONTEXT="minikube"
GKE_CONTEXT="${GKE_CONTEXT:-gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}}"

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
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    # Check if both contexts exist
    if ! kubectl config get-contexts | grep -q "$MINIKUBE_CONTEXT"; then
        print_error "Minikube context '$MINIKUBE_CONTEXT' not found"
        exit 1
    fi
    
    if ! kubectl config get-contexts | grep -q "$GKE_CONTEXT"; then
        print_warning "GKE context '$GKE_CONTEXT' not found"
        print_status "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    print_success "Prerequisites check completed"
}

# Function to backup data from minikube
backup_from_minikube() {
    print_status "Backing up data from minikube..."
    
    # Switch to minikube context
    kubectl config use-context "$MINIKUBE_CONTEXT"
    
    # Backup JupyterHub notebooks
    print_status "Backing up JupyterHub notebooks..."
    mkdir -p "$BACKUP_DIR/notebooks"
    
    # Get JupyterHub pods
    local hub_pods=$(kubectl get pods -n jupyterhub -l component=singleuser-server --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
    
    if [[ -n "$hub_pods" ]]; then
        while IFS= read -r pod; do
            if [[ -n "$pod" ]]; then
                print_status "Backing up notebooks from pod: $pod"
                kubectl cp "jupyterhub/$pod:/home/jovyan/work" "$BACKUP_DIR/notebooks/$pod" 2>/dev/null || print_warning "Failed to backup from $pod"
            fi
        done <<< "$hub_pods"
    else
        print_warning "No JupyterHub user pods found"
    fi
    
    # Backup shared notebooks if they exist
    local shared_pods=$(kubectl get pods -n jupyterhub -l app=jupyterhub,component=hub --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
    if [[ -n "$shared_pods" ]]; then
        local hub_pod=$(echo "$shared_pods" | head -n1)
        kubectl cp "jupyterhub/$hub_pod:/srv/jupyterhub" "$BACKUP_DIR/jupyterhub-config" 2>/dev/null || print_warning "Failed to backup JupyterHub config"
    fi
    
    # Backup MLflow data
    print_status "Backing up MLflow data..."
    mkdir -p "$BACKUP_DIR/mlflow"
    
    local mlflow_pod=$(kubectl get pods -n mlflow -l app=mlflow --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -n1)
    if [[ -n "$mlflow_pod" ]]; then
        kubectl cp "mlflow/$mlflow_pod:/mlflow" "$BACKUP_DIR/mlflow/artifacts" 2>/dev/null || print_warning "Failed to backup MLflow artifacts"
        
        # Export MLflow database if using SQLite
        kubectl exec -n mlflow "$mlflow_pod" -- sqlite3 /mlflow/mlflow.db .dump > "$BACKUP_DIR/mlflow/database.sql" 2>/dev/null || print_warning "Failed to backup MLflow database"
    else
        print_warning "No MLflow pods found"
    fi
    
    # Backup Ray checkpoints and logs
    print_status "Backing up Ray data..."
    mkdir -p "$BACKUP_DIR/ray"
    
    local ray_head=$(kubectl get pods -n ray-system -l ray.io/node-type=head --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -n1)
    if [[ -n "$ray_head" ]]; then
        kubectl cp "ray-system/$ray_head:/tmp/ray" "$BACKUP_DIR/ray/logs" 2>/dev/null || print_warning "Failed to backup Ray logs"
    else
        print_warning "No Ray head pod found"
    fi
    
    # Backup persistent volume data
    print_status "Backing up persistent volume data..."
    mkdir -p "$BACKUP_DIR/pv-data"
    
    # Get all PVCs and backup their data
    local pvcs=$(kubectl get pvc -A --no-headers -o custom-columns=":metadata.namespace,:metadata.name" 2>/dev/null || echo "")
    if [[ -n "$pvcs" ]]; then
        while IFS= read -r pvc_info; do
            if [[ -n "$pvc_info" ]]; then
                local namespace=$(echo "$pvc_info" | awk '{print $1}')
                local pvc_name=$(echo "$pvc_info" | awk '{print $2}')
                
                # Find pods using this PVC
                local pods=$(kubectl get pods -n "$namespace" -o json | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" 2>/dev/null || echo "")
                
                if [[ -n "$pods" ]]; then
                    local pod=$(echo "$pods" | head -n1)
                    print_status "Backing up PVC $pvc_name from pod $pod in namespace $namespace"
                    
                    # Find mount path
                    local mount_path=$(kubectl get pod -n "$namespace" "$pod" -o json | jq -r ".spec.containers[0].volumeMounts[] | select(.name | contains(\"$pvc_name\")) | .mountPath" 2>/dev/null || echo "/data")
                    
                    kubectl cp "$namespace/$pod:$mount_path" "$BACKUP_DIR/pv-data/$namespace-$pvc_name" 2>/dev/null || print_warning "Failed to backup PVC $pvc_name"
                fi
            fi
        done <<< "$pvcs"
    fi
    
    # Backup Kubernetes configurations
    print_status "Backing up Kubernetes configurations..."
    mkdir -p "$BACKUP_DIR/k8s-configs"
    
    # Export important resources
    kubectl get configmaps -A -o yaml > "$BACKUP_DIR/k8s-configs/configmaps.yaml" 2>/dev/null || true
    kubectl get secrets -A -o yaml > "$BACKUP_DIR/k8s-configs/secrets.yaml" 2>/dev/null || true
    kubectl get pvc -A -o yaml > "$BACKUP_DIR/k8s-configs/pvcs.yaml" 2>/dev/null || true
    
    print_success "Backup from minikube completed"
}

# Function to restore data to GKE
restore_to_gke() {
    print_status "Restoring data to GKE..."
    
    # Switch to GKE context
    kubectl config use-context "$GKE_CONTEXT"
    
    # Wait for pods to be ready
    print_status "Waiting for GKE pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=ml-platform -A --timeout=300s || print_warning "Some pods may not be ready"
    
    # Restore JupyterHub notebooks
    print_status "Restoring JupyterHub notebooks..."
    
    if [[ -d "$BACKUP_DIR/notebooks" ]]; then
        # Create a temporary pod for file transfer
        kubectl run file-transfer --image=busybox --rm -i --restart=Never --command -- sleep 3600 &
        local transfer_pod_pid=$!
        sleep 10
        
        # Copy notebooks to shared storage
        if kubectl get pvc filestore-pvc &>/dev/null; then
            kubectl cp "$BACKUP_DIR/notebooks" file-transfer:/shared-notebooks 2>/dev/null || print_warning "Failed to restore notebooks to shared storage"
        fi
        
        # Kill transfer pod
        kill $transfer_pod_pid 2>/dev/null || true
        kubectl delete pod file-transfer --ignore-not-found=true
    fi
    
    # Restore MLflow data
    print_status "Restoring MLflow data..."
    
    if [[ -d "$BACKUP_DIR/mlflow" ]]; then
        local mlflow_pod=$(kubectl get pods -n mlflow -l app=mlflow --no-headers -o custom-columns=":metadata.name" | head -n1)
        if [[ -n "$mlflow_pod" ]]; then
            # Wait for MLflow to be ready
            kubectl wait --for=condition=ready pod -n mlflow -l app=mlflow --timeout=120s
            
            # Restore artifacts
            if [[ -d "$BACKUP_DIR/mlflow/artifacts" ]]; then
                kubectl cp "$BACKUP_DIR/mlflow/artifacts" "mlflow/$mlflow_pod:/mlflow/" 2>/dev/null || print_warning "Failed to restore MLflow artifacts"
            fi
            
            # Restore database
            if [[ -f "$BACKUP_DIR/mlflow/database.sql" ]]; then
                kubectl cp "$BACKUP_DIR/mlflow/database.sql" "mlflow/$mlflow_pod:/tmp/database.sql"
                kubectl exec -n mlflow "$mlflow_pod" -- sqlite3 /mlflow/mlflow.db < /tmp/database.sql 2>/dev/null || print_warning "Failed to restore MLflow database"
            fi
        fi
    fi
    
    # Restore to shared storage
    print_status "Restoring data to shared storage..."
    
    if kubectl get pvc filestore-pvc &>/dev/null && [[ -d "$BACKUP_DIR/pv-data" ]]; then
        # Create a temporary pod with shared storage mounted
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: data-restore-pod
spec:
  containers:
  - name: restore
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: shared-storage
      mountPath: /shared
  volumes:
  - name: shared-storage
    persistentVolumeClaim:
      claimName: filestore-pvc
  restartPolicy: Never
EOF
        
        # Wait for pod to be ready
        kubectl wait --for=condition=ready pod data-restore-pod --timeout=120s
        
        # Copy data to shared storage
        for backup_dir in "$BACKUP_DIR/pv-data"/*; do
            if [[ -d "$backup_dir" ]]; then
                local dir_name=$(basename "$backup_dir")
                print_status "Restoring $dir_name to shared storage"
                kubectl cp "$backup_dir" "data-restore-pod:/shared/$dir_name" 2>/dev/null || print_warning "Failed to restore $dir_name"
            fi
        done
        
        # Cleanup
        kubectl delete pod data-restore-pod --ignore-not-found=true
    fi
    
    print_success "Data restoration to GKE completed"
}

# Function to verify migration
verify_migration() {
    print_status "Verifying migration..."
    
    # Switch to GKE context
    kubectl config use-context "$GKE_CONTEXT"
    
    # Check if pods are running
    print_status "Checking pod status..."
    kubectl get pods -A | grep -E "(jupyterhub|ray|mlflow|monitoring)"
    
    # Check persistent volumes
    print_status "Checking persistent volumes..."
    kubectl get pv,pvc -A
    
    # Check if shared storage has data
    if kubectl get pvc filestore-pvc &>/dev/null; then
        print_status "Checking shared storage contents..."
        kubectl run storage-check --image=busybox --rm -i --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "storage-check",
      "image": "busybox",
      "command": ["ls", "-la", "/shared"],
      "volumeMounts": [{
        "name": "shared-storage",
        "mountPath": "/shared"
      }]
    }],
    "volumes": [{
      "name": "shared-storage",
      "persistentVolumeClaim": {
        "claimName": "filestore-pvc"
      }
    }]
  }
}' || print_warning "Could not check shared storage"
    fi
    
    print_success "Migration verification completed"
}

# Function to generate migration report
generate_report() {
    print_status "Generating migration report..."
    
    local report_file="$BACKUP_DIR/migration-report.txt"
    
    cat > "$report_file" <<EOF
ML Platform Migration Report
===========================
Date: $(date)
Source: Minikube
Destination: GKE

Backup Location: $BACKUP_DIR

Components Migrated:
- JupyterHub notebooks: $(find "$BACKUP_DIR/notebooks" -type f 2>/dev/null | wc -l) files
- MLflow artifacts: $(find "$BACKUP_DIR/mlflow" -type f 2>/dev/null | wc -l) files
- Ray data: $(find "$BACKUP_DIR/ray" -type f 2>/dev/null | wc -l) files
- Persistent volume data: $(find "$BACKUP_DIR/pv-data" -type f 2>/dev/null | wc -l) files

Kubernetes Resources:
- ConfigMaps: $(grep -c "kind: ConfigMap" "$BACKUP_DIR/k8s-configs/configmaps.yaml" 2>/dev/null || echo "0")
- Secrets: $(grep -c "kind: Secret" "$BACKUP_DIR/k8s-configs/secrets.yaml" 2>/dev/null || echo "0")
- PVCs: $(grep -c "kind: PersistentVolumeClaim" "$BACKUP_DIR/k8s-configs/pvcs.yaml" 2>/dev/null || echo "0")

Next Steps:
1. Verify applications are working correctly
2. Update DNS/ingress configurations
3. Update CI/CD pipelines
4. Test ML workloads
5. Clean up minikube environment (optional)

EOF
    
    print_success "Migration report generated: $report_file"
    cat "$report_file"
}

# Main function
main() {
    print_status "Starting ML Platform data migration..."
    echo "Source: $MINIKUBE_CONTEXT"
    echo "Destination: $GKE_CONTEXT"
    echo "Backup Directory: $BACKUP_DIR"
    echo
    
    case "${1:-all}" in
        "backup")
            check_prerequisites
            backup_from_minikube
            generate_report
            ;;
        "restore")
            restore_to_gke
            verify_migration
            ;;
        "verify")
            verify_migration
            ;;
        "all")
            check_prerequisites
            backup_from_minikube
            restore_to_gke
            verify_migration
            generate_report
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [action]"
            echo
            echo "Actions:"
            echo "  backup   - Backup data from minikube only"
            echo "  restore  - Restore data to GKE only"
            echo "  verify   - Verify migration only"
            echo "  all      - Complete migration (default)"
            echo "  help     - Show this help"
            echo
            echo "Environment variables:"
            echo "  GKE_CONTEXT     - GKE kubectl context name"
            echo "  PROJECT_ID      - GCP project ID"
            echo "  REGION          - GCP region"
            echo "  CLUSTER_NAME    - GKE cluster name"
            ;;
        *)
            print_error "Unknown action: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
    
    print_success "Migration operation completed!"
}

# Run main function with all arguments
main "$@"
