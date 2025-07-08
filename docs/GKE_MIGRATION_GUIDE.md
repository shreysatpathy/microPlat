# ML Platform Migration Guide: Minikube to GKE

This guide walks you through migrating your ML Platform from minikube to Google Kubernetes Engine (GKE).

## Overview

The migration involves:
1. **Infrastructure Setup**: Deploy GKE cluster with Terraform
2. **Storage Migration**: Move from local storage to GCS/Filestore
3. **Application Updates**: Update Helm charts for GKE compatibility
4. **CI/CD Updates**: Configure pipelines for Artifact Registry
5. **Data Migration**: Transfer existing data and configurations

## Prerequisites

### Required Tools
- Google Cloud SDK (`gcloud`)
- Terraform >= 1.0
- kubectl
- Helm >= 3.0
- Docker

### GCP Setup
1. **Create GCP Project** (if not exists):
   ```bash
   gcloud projects create YOUR_PROJECT_ID
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Enable Billing**: Ensure billing is enabled for your project

3. **Set up Authentication**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

## Phase 1: Infrastructure Deployment

### 1.1 Configure Terraform Variables

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your project settings:
```hcl
project_id   = "your-gcp-project-id"
project_name = "ml-platform"
environment  = "dev"
region       = "us-central1"
```

### 1.2 Deploy Infrastructure

Use the deployment script:
```bash
chmod +x scripts/deploy-gke.sh
./scripts/deploy-gke.sh --project-id YOUR_PROJECT_ID
```

Or deploy manually:
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### 1.3 Configure kubectl

```bash
# Get cluster credentials
gcloud container clusters get-credentials ml-platform-dev-gke \
    --region us-central1 \
    --project YOUR_PROJECT_ID

# Verify connection
kubectl cluster-info
```

## Phase 2: Update Helm Charts

### 2.1 Update Storage Classes

Replace minikube storage with GKE equivalents:

**JupyterHub** (`charts/jupyterhub/values.yaml`):
```yaml
hub:
  db:
    pvc:
      storageClassName: standard-rwo
  
singleuser:
  storage:
    type: dynamic
    dynamic:
      storageClass: standard-rwo
    homeMountPath: /home/jovyan
    extraVolumes:
      - name: shared-storage
        persistentVolumeClaim:
          claimName: filestore-pvc
    extraVolumeMounts:
      - name: shared-storage
        mountPath: /shared
```

**MLflow** (`charts/mlflow/values.yaml`):
```yaml
backendStore:
  postgres:
    enabled: true
    persistence:
      storageClass: standard-rwo

artifactStore:
  gcs:
    enabled: true
    bucket: "ml-platform-dev-mlflow-artifacts"
    
serviceAccount:
  create: true
  annotations:
    iam.gke.io/gcp-service-account: ml-platform-dev-mlflow@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

**Ray Cluster** (`charts/ray-cluster/values.yaml`):
```yaml
head:
  serviceAccount:
    create: true
    annotations:
      iam.gke.io/gcp-service-account: ml-platform-dev-ray@YOUR_PROJECT_ID.iam.gserviceaccount.com
  
  resources:
    requests:
      cpu: "2"
      memory: "8Gi"
    limits:
      cpu: "4"
      memory: "16Gi"

worker:
  replicas: 2
  minReplicas: 0
  maxReplicas: 10
  
  serviceAccount:
    create: true
    annotations:
      iam.gke.io/gcp-service-account: ml-platform-dev-ray@YOUR_PROJECT_ID.iam.gserviceaccount.com
  
  tolerations:
    - key: "ml-workload"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
  
  nodeSelector:
    workload: "ml-compute"
```

### 2.2 Create Filestore PVC

Create persistent volume for Filestore:

```yaml
# manifests/storage/filestore-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: filestore-pv
spec:
  capacity:
    storage: 1Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: FILESTORE_IP  # From Terraform output
    path: /shared
  mountOptions:
    - hard
    - intr
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: filestore-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Ti
  volumeName: filestore-pv
```

### 2.3 Update Monitoring Stack

Update `charts/kube-prometheus-stack/values.yaml`:
```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard-rwo
          resources:
            requests:
              storage: 50Gi

grafana:
  persistence:
    enabled: true
    storageClassName: standard-rwo
    size: 10Gi
  
  serviceAccount:
    create: true
    annotations:
      iam.gke.io/gcp-service-account: ml-platform-dev-monitoring@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

## Phase 3: Update CI/CD Pipeline

### 3.1 Update GitHub Actions

Update `.github/workflows/build-push.yml`:

```yaml
env:
  REGISTRY: us-central1-docker.pkg.dev
  PROJECT_ID: YOUR_PROJECT_ID
  REPOSITORY: ml-platform-dev-images

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}
      
      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker us-central1-docker.pkg.dev
      
      - name: Build and push images
        run: |
          docker build -t $REGISTRY/$PROJECT_ID/$REPOSITORY/notebook:$GITHUB_SHA docker/notebook/
          docker push $REGISTRY/$PROJECT_ID/$REPOSITORY/notebook:$GITHUB_SHA
```

### 3.2 Update Image References

Update all Helm chart values to use Artifact Registry:
```yaml
image:
  repository: us-central1-docker.pkg.dev/YOUR_PROJECT_ID/ml-platform-dev-images/notebook
  tag: latest
```

## Phase 4: Data Migration

### 4.1 Export Minikube Data

```bash
# Export MLflow data
kubectl exec -it mlflow-deployment-xxx -- pg_dump mlflow > mlflow_backup.sql

# Export notebooks
kubectl cp jupyterhub-namespace/jupyter-user-pod:/home/jovyan ./notebooks-backup

# Export datasets
kubectl cp ray-namespace/ray-head-pod:/data ./datasets-backup
```

### 4.2 Import to GKE

```bash
# Upload to GCS
gsutil -m cp -r ./notebooks-backup gs://ml-platform-dev-notebooks/
gsutil -m cp -r ./datasets-backup gs://ml-platform-dev-datasets/

# Restore MLflow database
kubectl exec -it mlflow-deployment-xxx -- psql mlflow < mlflow_backup.sql
```

## Phase 5: Deploy Applications

### 5.1 Deploy ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 5.2 Apply ArgoCD Applications

```bash
kubectl apply -f manifests/applications/
```

### 5.3 Sync Applications

Access ArgoCD UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Navigate to `https://localhost:8080` and sync all applications.

## Phase 6: Verification

### 6.1 Test JupyterHub

```bash
kubectl port-forward svc/proxy-public -n jupyterhub 8000:80
```

Access JupyterHub at `http://localhost:8000` and verify:
- User can log in
- Notebooks can access shared storage
- Ray cluster connection works

### 6.2 Test MLflow

```bash
kubectl port-forward svc/mlflow -n mlflow 5000:5000
```

Access MLflow at `http://localhost:5000` and verify:
- Experiments are visible
- Artifacts are accessible
- New experiments can be created

### 6.3 Test Ray Cluster

```bash
kubectl port-forward svc/ray-head -n ray-system 8265:8265
```

Access Ray dashboard at `http://localhost:8265` and verify:
- Cluster is healthy
- Workers are connected
- Jobs can be submitted

### 6.4 Test Monitoring

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```

Access Grafana at `http://localhost:3000` (admin/prom-operator) and verify:
- Dashboards are loading
- Metrics are being collected
- Alerts are configured

## Troubleshooting

### Common Issues

1. **Pod Stuck in Pending**: Check node selectors and taints
2. **Storage Issues**: Verify PVC creation and storage classes
3. **Authentication Issues**: Check Workload Identity bindings
4. **Network Issues**: Verify firewall rules and network policies

### Useful Commands

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check storage
kubectl get pv,pvc --all-namespaces

# Check service accounts
kubectl get serviceaccounts --all-namespaces

# Check Workload Identity
kubectl describe serviceaccount SERVICE_ACCOUNT_NAME -n NAMESPACE
```

## Rollback Plan

If migration fails, you can:

1. **Keep minikube running** during migration
2. **Export data regularly** during migration
3. **Use Terraform destroy** to clean up GKE resources
4. **Restore minikube** from backups if needed

## Cost Optimization

After successful migration:

1. **Use Preemptible/Spot instances** for ML workloads
2. **Enable cluster autoscaling**
3. **Set up budget alerts**
4. **Use lifecycle policies** for storage
5. **Monitor resource usage** with GKE usage metering

## Next Steps

1. Set up production environment
2. Configure backup and disaster recovery
3. Implement security scanning
4. Set up log aggregation
5. Configure alerting and monitoring

## Support

For issues during migration:
1. Check the troubleshooting section
2. Review GKE documentation
3. Check project issues on GitHub
4. Contact the platform team
