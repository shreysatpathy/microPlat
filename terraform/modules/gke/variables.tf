variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "network" {
  description = "The VPC network name"
  type        = string
}

variable "subnetwork" {
  description = "The VPC subnetwork name"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "The IP range in CIDR notation for the master network"
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "List of master authorized networks"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
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
  default = []
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
