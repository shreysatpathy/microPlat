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

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "ci_service_account" {
  description = "CI service account email for pushing images"
  type        = string
  default     = ""
}

variable "developer_service_account" {
  description = "Developer service account email for pushing images"
  type        = string
  default     = ""
}
