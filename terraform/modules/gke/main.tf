# GKE Cluster module for ML Platform

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.name_prefix}-gke"
  location = var.region
  
  # Network configuration
  network    = var.network
  subnetwork = var.subnetwork
  
  # IP allocation policy for secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }
  
  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }
  
  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Network policy
  network_policy {
    enabled = true
  }
  
  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    network_policy_config {
      disabled = false
    }
    
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
  
  # Logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"
  
  # Security configuration
  enable_shielded_nodes = true
  
  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Maintenance policy
  maintenance_policy {
    recurring_window {
      start_time = "2023-01-01T02:00:00Z"
      end_time   = "2023-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }
  
  # Release channel
  release_channel {
    channel = "REGULAR"
  }
  
  project = var.project_id
  
  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# Node pools
resource "google_container_node_pool" "node_pools" {
  for_each = { for pool in var.node_pools : pool.name => pool }
  
  name       = each.value.name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  
  initial_node_count = each.value.initial_node_count
  
  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }
  
  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    
    # Service account
    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Labels
    labels = merge(var.labels, each.value.labels)
    
    # Taints
    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
    
    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Workload metadata config
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Preemptible/Spot instances
    preemptible = each.value.preemptible
    spot        = each.value.spot
    
    tags = ["gke-node", "${var.name_prefix}-gke-node"]
  }
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
  
  project = var.project_id
  
  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# GPU node pool (conditional)
resource "google_container_node_pool" "gpu_pool" {
  count = var.enable_gpu ? 1 : 0
  
  name       = var.gpu_node_pool.name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  
  initial_node_count = var.gpu_node_pool.initial_node_count
  
  autoscaling {
    min_node_count = var.gpu_node_pool.min_count
    max_node_count = var.gpu_node_pool.max_count
  }
  
  node_config {
    machine_type = var.gpu_node_pool.machine_type
    disk_size_gb = var.gpu_node_pool.disk_size_gb
    disk_type    = var.gpu_node_pool.disk_type
    
    # GPU configuration
    guest_accelerator {
      type  = var.gpu_node_pool.accelerator_type
      count = var.gpu_node_pool.accelerator_count
    }
    
    # Service account
    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Labels
    labels = merge(var.labels, {
      "workload" = "gpu"
    })
    
    # Taints for GPU nodes
    taint {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
    
    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Workload metadata config
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Preemptible/Spot instances
    preemptible = var.gpu_node_pool.preemptible
    spot        = var.gpu_node_pool.spot
    
    tags = ["gke-node", "${var.name_prefix}-gke-gpu-node"]
  }
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
  
  project = var.project_id
  
  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# Service account for GKE nodes
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.name_prefix}-gke-node-sa"
  display_name = "GKE Node Service Account"
  project      = var.project_id
}

# IAM bindings for GKE node service account
resource "google_project_iam_member" "gke_node_sa_bindings" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}
