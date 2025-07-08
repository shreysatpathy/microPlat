# Variables for ML Platform GKE deployment

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "ml-platform"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "master_ipv4_cidr_block" {
  description = "The IP range in CIDR notation for the master network"
  type        = string
  default     = "172.16.0.0/28"
}

variable "node_pools" {
  description = "List of node pool configurations"
  type = list(object({
    name               = string
    machine_type       = string
    min_count          = number
    max_count          = number
    initial_node_count = number
    disk_size_gb       = number
    disk_type          = string
    preemptible        = bool
    spot               = bool
    labels             = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  default = [
    {
      name               = "general-purpose"
      machine_type       = "e2-standard-4"
      min_count          = 1
      max_count          = 10
      initial_node_count = 2
      disk_size_gb       = 100
      disk_type          = "pd-standard"
      preemptible        = false
      spot               = false
      labels = {
        workload = "general"
      }
      taints = []
    },
    {
      name               = "ml-workload"
      machine_type       = "n1-standard-8"
      min_count          = 0
      max_count          = 5
      initial_node_count = 0
      disk_size_gb       = 200
      disk_type          = "pd-ssd"
      preemptible        = true
      spot               = false
      labels = {
        workload = "ml-compute"
      }
      taints = [
        {
          key    = "ml-workload"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  ]
}

variable "enable_gpu" {
  description = "Enable GPU support in the cluster"
  type        = bool
  default     = false
}

variable "gpu_node_pool" {
  description = "GPU node pool configuration"
  type = object({
    name               = string
    machine_type       = string
    accelerator_type   = string
    accelerator_count  = number
    min_count          = number
    max_count          = number
    initial_node_count = number
    disk_size_gb       = number
    disk_type          = string
    preemptible        = bool
    spot               = bool
  })
  default = {
    name               = "gpu-pool"
    machine_type       = "n1-standard-4"
    accelerator_type   = "nvidia-tesla-t4"
    accelerator_count  = 1
    min_count          = 0
    max_count          = 3
    initial_node_count = 0
    disk_size_gb       = 200
    disk_type          = "pd-ssd"
    preemptible        = true
    spot               = false
  }
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB"
  type        = number
  default     = 1024
}

variable "filestore_tier" {
  description = "Filestore tier (BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD)"
  type        = string
  default     = "BASIC_HDD"
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for the cluster"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy for the cluster"
  type        = bool
  default     = true
}

variable "enable_private_nodes" {
  description = "Enable private nodes for the cluster"
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "List of master authorized networks"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  ]
}
