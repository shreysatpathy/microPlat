# ML Platform GKE Infrastructure

This directory contains Terraform configuration for deploying the ML Platform on Google Kubernetes Engine (GKE).

## Architecture

The infrastructure includes:

- **GKE Cluster**: Private cluster with multiple node pools
- **VPC Network**: Custom VPC with private subnets and Cloud NAT
- **Storage**: Google Cloud Storage buckets and Filestore for shared filesystem
- **IAM**: Service accounts with Workload Identity for secure pod-to-GCP authentication
- **Artifact Registry**: Container and Python package repositories

## Prerequisites

1. **Google Cloud SDK**: Install and authenticate
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform**: Install Terraform >= 1.0

3. **Enable APIs**: Enable required GCP APIs
   ```bash
   gcloud services enable container.googleapis.com
   gcloud services enable compute.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable file.googleapis.com
   gcloud services enable artifactregistry.googleapis.com
   gcloud services enable iam.googleapis.com
   ```

## Deployment

1. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your project settings
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Plan Deployment**:
   ```bash
   terraform plan
   ```

4. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

5. **Configure kubectl**:
   ```bash
   # Get the kubectl config command from terraform output
   terraform output kubectl_config_command
   # Run the command to configure kubectl
   ```

## Configuration

### Node Pools

The cluster includes multiple node pools:

- **general-purpose**: Standard nodes for system workloads
- **ml-workload**: High-memory nodes for ML training (with taints)
- **gpu-pool**: GPU nodes for ML training (optional)

### Storage

- **GCS Buckets**:
  - `mlflow-artifacts`: MLflow experiment artifacts
  - `notebooks`: Jupyter notebook storage
  - `datasets`: Training datasets
  - `models`: Trained model storage

- **Filestore**: Shared NFS filesystem for cross-pod data sharing

### Security

- **Private Cluster**: Nodes have no public IPs
- **Workload Identity**: Secure pod-to-GCP authentication
- **Network Policies**: Pod-to-pod communication control
- **Service Accounts**: Least-privilege access for each component

## Outputs

After deployment, Terraform provides:

- Cluster connection details
- Storage bucket names and URLs
- Service account emails
- Workload Identity configurations

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

**Warning**: This will delete all resources including data in GCS buckets and Filestore.

## Module Structure

```
modules/
├── vpc/          # VPC and networking
├── gke/          # GKE cluster and node pools
├── storage/      # GCS buckets and Filestore
├── iam/          # Service accounts and IAM
└── registry/     # Artifact Registry
```

## Next Steps

After infrastructure deployment:

1. Update Helm chart values with GKE-specific configurations
2. Deploy ArgoCD to the cluster
3. Configure GitOps workflows
4. Deploy ML platform applications

See the main project README for application deployment instructions.
