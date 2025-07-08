# Main Terraform configuration for ML Platform on GKE
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Local values for resource naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_labels = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

# VPC and Networking
module "vpc" {
  source = "./modules/vpc"
  
  project_id   = var.project_id
  name_prefix  = local.name_prefix
  region       = var.region
  labels       = local.common_labels
}

# GKE Cluster
module "gke" {
  source = "./modules/gke"
  
  project_id                = var.project_id
  name_prefix              = local.name_prefix
  region                   = var.region
  network                  = module.vpc.network_name
  subnetwork               = module.vpc.subnetwork_name
  master_ipv4_cidr_block   = var.master_ipv4_cidr_block
  labels                   = local.common_labels
  
  # Node pool configuration
  node_pools = var.node_pools
  
  depends_on = [module.vpc]
}

# Storage (GCS and Filestore)
module "storage" {
  source = "./modules/storage"
  
  project_id  = var.project_id
  name_prefix = local.name_prefix
  region      = var.region
  labels      = local.common_labels
}

# IAM and Service Accounts
module "iam" {
  source = "./modules/iam"
  
  project_id  = var.project_id
  name_prefix = local.name_prefix
  labels      = local.common_labels
}

# Artifact Registry
module "registry" {
  source = "./modules/registry"
  
  project_id  = var.project_id
  name_prefix = local.name_prefix
  region      = var.region
  labels      = local.common_labels
}
