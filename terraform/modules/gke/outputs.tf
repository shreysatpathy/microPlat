output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.primary.master_auth.0.cluster_ca_certificate
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.primary.location
}

output "node_pools" {
  description = "Node pool names"
  value       = [for pool in google_container_node_pool.node_pools : pool.name]
}

output "gpu_node_pool" {
  description = "GPU node pool name (if enabled)"
  value       = var.enable_gpu ? google_container_node_pool.gpu_pool[0].name : null
}

output "node_service_account" {
  description = "GKE node service account email"
  value       = google_service_account.gke_node_sa.email
}
