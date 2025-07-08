# ML Platform Migration Guide: Minikube to GKE

This guide provides step-by-step instructions for migrating your ML platform from minikube to Google Kubernetes Engine (GKE).

## Overview

The migration involves:
- Deploying GKE infrastructure using Terraform
- Using GKE-optimized Helm charts in the `gkeCharts/` directory
- Configuring Workload Identity for secure GCP service access
- Setting up persistent storage with GCS and Filestore
- Maintaining GitOps workflow with ArgoCD

## Prerequisites

### Required Tools
```bash
# Install required tools
gcloud components install kubectl
curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/
```

### GCP Setup
```bash
# Authenticate with GCP
gcloud auth login
gcloud auth application-default login

# Set your project
export PROJECT_ID=your-gcp-project-id
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable file.googleapis.com
gcloud services enable artifactregistry.googleapis.com
```

## Migration Steps

### Step 1: Deploy GKE Infrastructure

```bash
# Deploy infrastructure using Terraform
make -f Makefile.gke deploy-infrastructure

# Or manually:
cd terraform
terraform init
terraform plan -var="project_id=$PROJECT_ID"
terraform apply -var="project_id=$PROJECT_ID"
```

This creates:
- GKE cluster with multiple node pools
- Filestore instance for shared storage
- VPC and networking components
- IAM service accounts with Workload Identity

### Step 2: Connect to GKE Cluster

```bash
# Connect kubectl to the new cluster
make -f Makefile.gke connect-cluster

# Verify connection
kubectl get nodes
```

### Step 3: Update Configuration

Before deploying, update the following placeholders in the GKE charts:

1. **Repository URLs**: Update GitHub repository URLs in `manifests/gke-applications/*.yaml`
2. **Project ID**: Automatically updated by deployment script
3. **Filestore IP**: Automatically retrieved from Terraform output

### Step 4: Deploy ML Platform Components

#### Option A: Deploy All Components at Once
```bash
# Quick deployment of all components
make -f Makefile.gke deploy-all
```

#### Option B: Deploy Components Individually
```bash
# Deploy in recommended order
make -f Makefile.gke deploy-storage
make -f Makefile.gke deploy-monitoring
make -f Makefile.gke deploy-mlflow
make -f Makefile.gke deploy-ray
make -f Makefile.gke deploy-jupyterhub
```

#### Option C: GitOps Deployment
```bash
# Deploy ArgoCD
make -f Makefile.gke deploy-argocd

# Deploy applications via GitOps
make -f Makefile.gke deploy-gitops-apps
```

### Step 5: Verify Deployment

```bash
# Check status of all components
make -f Makefile.gke status

# View logs
make -f Makefile.gke logs

# Set up port forwarding for access
make -f Makefile.gke port-forward-all
```

### Step 6: Access Applications

After port forwarding is set up:

- **JupyterHub**: http://localhost:8080 (any username, password: `mlplatform`)
- **Grafana**: http://localhost:3000 (admin/admin123)
- **Prometheus**: http://localhost:9090
- **MLflow**: http://localhost:5000
- **Ray Dashboard**: http://localhost:8265
- **ArgoCD**: http://localhost:8081

## Data Migration

### Migrate Jupyter Notebooks
```bash
# Copy notebooks from minikube to GKE
kubectl cp <minikube-pod>:/home/jovyan/work ./notebooks
kubectl cp ./notebooks <gke-pod>:/home/jovyan/work
```

### Migrate MLflow Experiments
```bash
# Export experiments from minikube MLflow
mlflow experiments search --experiment-ids 0,1,2 --output-format json > experiments.json

# Import to GKE MLflow (after port-forwarding)
export MLFLOW_TRACKING_URI=http://localhost:5000
python scripts/import_mlflow_experiments.py experiments.json
```

### Migrate Ray Workloads
Update Ray connection strings in your code:
```python
# Old (minikube)
ray.init("ray://localhost:10001")

# New (GKE)
ray.init("ray://ray-head.ray-system:10001")
```

## Configuration Differences

### Storage
| Component | Minikube | GKE |
|-----------|----------|-----|
| Persistent Volumes | hostPath | GKE Standard SSD |
| Shared Storage | None | Filestore NFS |
| Object Storage | Local files | Google Cloud Storage |

### Networking
| Component | Minikube | GKE |
|-----------|----------|-----|
| Service Type | NodePort | ClusterIP + Ingress |
| Load Balancer | None | GCP Load Balancer |
| DNS | minikube.local | cluster.local |

### Security
| Component | Minikube | GKE |
|-----------|----------|-----|
| Authentication | None | Workload Identity |
| RBAC | Basic | Full RBAC |
| Network Policies | None | Calico/GKE |

## Monitoring and Observability

### Prometheus Metrics
The GKE deployment includes enhanced monitoring:
- Ray cluster metrics
- JupyterHub user metrics
- MLflow experiment tracking
- GKE-specific node and pod metrics

### Grafana Dashboards
Pre-configured dashboards for:
- Kubernetes cluster overview
- Ray cluster performance
- JupyterHub usage
- MLflow experiment trends

### Alerting
Custom alerts for:
- Ray worker failures
- JupyterHub pod crashes
- MLflow server downtime
- Storage capacity issues

## Cost Optimization

### Node Pools
- **General Purpose**: For system components (e2-standard-4)
- **ML Workloads**: For compute-intensive tasks (n1-standard-8)
- **GPU Nodes**: For ML training (n1-standard-4 + T4 GPU)

### Preemptible Instances
Ray workers use preemptible instances to reduce costs by ~70%.

### Auto-scaling
- Cluster autoscaler for nodes
- Horizontal Pod Autoscaler for applications
- Vertical Pod Autoscaler for resource optimization

## Troubleshooting

### Common Issues

#### 1. Filestore PVC Not Binding
```bash
# Check Filestore status
kubectl describe pv filestore-pv
kubectl describe pvc filestore-pvc

# Verify Filestore IP
gcloud filestore instances list
```

#### 2. Workload Identity Issues
```bash
# Check service account annotations
kubectl get sa -A -o yaml | grep workload-identity

# Test GCP access from pod
kubectl run test-pod --image=google/cloud-sdk:slim --rm -it -- bash
gcloud auth list
```

#### 3. Ray Cluster Not Starting
```bash
# Check Ray operator logs
kubectl logs -n ray-system -l app.kubernetes.io/name=kuberay-operator

# Check Ray head pod
kubectl describe pod -n ray-system -l ray.io/node-type=head
```

#### 4. JupyterHub Login Issues
```bash
# Check hub pod logs
kubectl logs -n jupyterhub -l component=hub

# Reset admin password
kubectl delete secret hub-secret -n jupyterhub
```

### Debugging Commands
```bash
# Get all resources
kubectl get all -A

# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -A

# Check persistent volumes
kubectl get pv,pvc -A
```

## Rollback Plan

If you need to rollback to minikube:

1. **Export Data**:
   ```bash
   # Export notebooks, experiments, and models
   kubectl cp <pod>:/data ./backup/
   ```

2. **Start Minikube**:
   ```bash
   minikube start
   kubectl config use-context minikube
   ```

3. **Deploy Original Charts**:
   ```bash
   make deploy-all  # Uses original charts/
   ```

4. **Import Data**:
   ```bash
   kubectl cp ./backup/ <pod>:/data/
   ```

## Next Steps

After successful migration:

1. **Set up CI/CD**: Update GitHub Actions to push images to Artifact Registry
2. **Configure Ingress**: Set up external access with SSL certificates
3. **Implement Backup**: Schedule regular backups of persistent data
4. **Monitor Costs**: Set up billing alerts and cost optimization
5. **Scale Testing**: Test with production workloads

## Support

For issues or questions:
- Check the troubleshooting section above
- Review logs: `make -f Makefile.gke logs`
- Check component status: `make -f Makefile.gke status`
- Consult GKE documentation: https://cloud.google.com/kubernetes-engine/docs

## Cleanup

To remove the GKE deployment:
```bash
# Remove applications
make -f Makefile.gke clean-apps

# Remove infrastructure
make -f Makefile.gke destroy-infrastructure
```

**Warning**: This will permanently delete all data and resources!
