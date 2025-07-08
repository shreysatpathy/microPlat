# Outputs for ML Platform GKE deployment

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "network_name" {
  description = "VPC network name"
  value       = module.vpc.network_name
}

output "subnetwork_name" {
  description = "VPC subnetwork name"
  value       = module.vpc.subnetwork_name
}

output "gcs_buckets" {
  description = "Created GCS bucket names"
  value       = module.storage.gcs_buckets
}

output "filestore_instance" {
  description = "Filestore instance details"
  value       = module.storage.filestore_instance
}

output "artifact_registry_repositories" {
  description = "Artifact Registry repository URLs"
  value       = module.registry.repository_urls
}

output "service_accounts" {
  description = "Created service account emails"
  value       = module.iam.service_account_emails
}

output "workload_identity_bindings" {
  description = "Workload Identity bindings"
  value       = module.iam.workload_identity_bindings
}

# Kubernetes configuration for kubectl
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}

# ArgoCD configuration
output "argocd_values" {
  description = "Values for ArgoCD Helm chart configuration"
  value = {
    cluster_name     = module.gke.cluster_name
    cluster_endpoint = module.gke.cluster_endpoint
    project_id       = var.project_id
    region           = var.region
  }
}
