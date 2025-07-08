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

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
}

variable "network_id" {
  description = "The VPC network ID for Filestore"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
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

# Service account variables for IAM bindings
variable "mlflow_service_account" {
  description = "MLflow service account email"
  type        = string
  default     = ""
}

variable "jupyter_service_account" {
  description = "JupyterHub service account email"
  type        = string
  default     = ""
}

variable "ray_service_account" {
  description = "Ray service account email"
  type        = string
  default     = ""
}
