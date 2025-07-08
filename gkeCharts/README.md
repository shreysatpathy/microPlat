# GKE-Optimized Helm Charts

This directory contains Helm charts specifically optimized for Google Kubernetes Engine (GKE) deployment of the ML Platform. These charts are designed to work with the Terraform infrastructure defined in the `terraform/` directory.

## Directory Structure

```
gkeCharts/
├── jupyterhub/          # JupyterHub chart for GKE
├── ray-cluster/         # Ray cluster chart for GKE
├── mlflow/             # MLflow tracking server chart
├── monitoring/         # Prometheus + Grafana monitoring stack
├── shared-storage/     # Shared storage manifests (Filestore PV/PVC)
└── README.md          # This file
```

## Key GKE Optimizations

### 1. **Workload Identity Integration**
- All service accounts are configured with Workload Identity annotations
- Secure authentication to GCP services without static keys
- IAM roles assigned through Terraform IAM module

### 2. **Storage Configuration**
- **Persistent Volumes**: Uses GKE standard storage classes (`standard-rwo`)
- **Shared Storage**: Filestore NFS for ReadWriteMany volumes
- **Object Storage**: GCS integration via CSI driver for notebooks and artifacts

### 3. **Node Pool Optimization**
- **General Purpose**: For control plane components (hub, monitoring)
- **ML Workload**: For compute-intensive Ray workers
- **GPU Nodes**: Optional GPU support for ML training (when enabled)

### 4. **Resource Management**
- Appropriate resource requests and limits for GKE
- Tolerations for preemptible nodes (cost optimization)
- Pod disruption budgets for high availability

### 5. **Networking**
- Network policies for pod isolation
- ClusterIP services for internal communication
- Optional ingress configuration for external access

## Prerequisites

1. **GKE Cluster**: Deploy using Terraform infrastructure
2. **Namespaces**: Create required namespaces
3. **Storage**: Deploy Filestore PV/PVC
4. **Service Accounts**: Apply Workload Identity service accounts

## Deployment Order

### 1. Create Namespaces
```bash
kubectl create namespace jupyterhub
kubectl create namespace ray-system
kubectl create namespace mlflow
kubectl create namespace monitoring
kubectl create namespace argocd
```

### 2. Deploy Shared Storage
```bash
# Update PROJECT_ID and FILESTORE_IP in the manifests
kubectl apply -f shared-storage/filestore-pv.yaml
kubectl apply -f shared-storage/filestore-pvc.yaml
kubectl apply -f shared-storage/service-accounts.yaml
```

### 3. Deploy Charts
```bash
# Add required Helm repositories
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

# Deploy monitoring first (for metrics collection)
helm install monitoring ./monitoring -n monitoring

# Deploy MLflow
helm install mlflow ./mlflow -n mlflow

# Deploy Ray cluster
helm install ray-cluster ./ray-cluster -n ray-system

# Deploy JupyterHub
helm install jupyterhub ./jupyterhub -n jupyterhub
```

## Configuration

### Environment-Specific Values

Before deployment, update the following placeholders in the values files:

- `PROJECT_ID`: Your GCP project ID
- `FILESTORE_IP`: IP address of the Filestore instance (from Terraform output)
- `REGISTRY_OWNER`: Your container registry organization

### Custom Values Files

Create environment-specific values files:

```bash
# Development environment
helm install jupyterhub ./jupyterhub -n jupyterhub -f values-dev.yaml

# Production environment
helm install jupyterhub ./jupyterhub -n jupyterhub -f values-prod.yaml
```

## Monitoring and Observability

### Prometheus Metrics
- **Ray Cluster**: Metrics exported on port 8080
- **MLflow**: Application metrics via custom endpoint
- **JupyterHub**: Hub and user pod metrics
- **Kubernetes**: Node and pod metrics via node-exporter

### Grafana Dashboards
- Ray Cluster dashboard (Grafana ID: 17400)
- JupyterHub dashboard (Grafana ID: 3991)
- Kubernetes cluster overview (Grafana ID: 7249)
- Node exporter dashboard (Grafana ID: 1860)

### Custom Alerts
- Ray cluster availability
- MLflow service health
- JupyterHub hub status
- Resource utilization thresholds

## Security Features

### Workload Identity
```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: "PROJECT_ID-service@PROJECT_ID.iam.gserviceaccount.com"
```

### Network Policies
- Namespace isolation
- Controlled inter-service communication
- External traffic restrictions

### Pod Security
- Non-root containers
- Read-only root filesystems where possible
- Security contexts with appropriate user/group IDs

## Scaling and Performance

### Horizontal Pod Autoscaler
```yaml
hpa:
  enabled: true
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### Ray Autoscaling
- Dynamic worker scaling based on workload
- Preemptible nodes for cost optimization
- GPU nodes for ML training workloads

### Resource Optimization
- Appropriate resource requests/limits
- Node affinity and anti-affinity rules
- Preemptible node tolerations

## Troubleshooting

### Common Issues

1. **Workload Identity Not Working**
   ```bash
   # Check service account annotations
   kubectl get sa -n <namespace> -o yaml
   
   # Verify IAM bindings
   gcloud iam service-accounts get-iam-policy PROJECT_ID-service@PROJECT_ID.iam.gserviceaccount.com
   ```

2. **Storage Issues**
   ```bash
   # Check PV/PVC status
   kubectl get pv,pvc -A
   
   # Check Filestore connectivity
   kubectl exec -it <pod> -- df -h /shared
   ```

3. **Pod Scheduling Issues**
   ```bash
   # Check node labels and taints
   kubectl get nodes --show-labels
   kubectl describe node <node-name>
   
   # Check pod events
   kubectl describe pod <pod-name> -n <namespace>
   ```

### Logs and Debugging
```bash
# Check application logs
kubectl logs -f <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Port forward for local access
kubectl port-forward svc/jupyterhub 8080:80 -n jupyterhub
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

## Production Considerations

### High Availability
- Multiple replicas for critical components
- Pod disruption budgets
- Cross-zone pod distribution

### Security Hardening
- Enable network policies
- Use private GKE cluster
- Regular security updates
- Secrets management with Google Secret Manager

### Backup and Recovery
- Persistent volume snapshots
- Database backups for MLflow
- Configuration backup in Git

### Cost Optimization
- Use preemptible nodes where appropriate
- Set appropriate resource limits
- Monitor and optimize resource usage
- Use GCS lifecycle policies for data retention

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review GKE and application logs
3. Consult the main project documentation
4. Contact the ML Platform team
