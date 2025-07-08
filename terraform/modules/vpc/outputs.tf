output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.vpc.id
}

output "subnetwork_name" {
  description = "The name of the GKE subnetwork"
  value       = google_compute_subnetwork.gke_subnet.name
}

output "subnetwork_id" {
  description = "The ID of the GKE subnetwork"
  value       = google_compute_subnetwork.gke_subnet.id
}

output "pods_range_name" {
  description = "The name of the pods secondary IP range"
  value       = google_compute_subnetwork.gke_subnet.secondary_ip_range[0].range_name
}

output "services_range_name" {
  description = "The name of the services secondary IP range"
  value       = google_compute_subnetwork.gke_subnet.secondary_ip_range[1].range_name
}
