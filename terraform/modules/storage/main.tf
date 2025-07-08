# Storage module for ML Platform (GCS and Filestore)

# GCS Buckets for different purposes
resource "google_storage_bucket" "mlflow_artifacts" {
  name     = "${var.name_prefix}-mlflow-artifacts"
  location = var.region
  project  = var.project_id
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Versioning for artifact tracking
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = var.labels
}

resource "google_storage_bucket" "notebooks" {
  name     = "${var.name_prefix}-notebooks"
  location = var.region
  project  = var.project_id
  
  # Versioning for notebook history
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = var.labels
}

resource "google_storage_bucket" "datasets" {
  name     = "${var.name_prefix}-datasets"
  location = var.region
  project  = var.project_id
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Versioning for dataset tracking
  versioning {
    enabled = true
  }
  
  # Lifecycle management for old versions
  lifecycle_rule {
    condition {
      age                = 365
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = var.labels
}

resource "google_storage_bucket" "models" {
  name     = "${var.name_prefix}-models"
  location = var.region
  project  = var.project_id
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Versioning for model tracking
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 180
    }
    action {
      type = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = var.labels
}

# Filestore instance for shared filesystem
resource "google_filestore_instance" "shared_storage" {
  name     = "${var.name_prefix}-shared-storage"
  location = var.zone
  tier     = var.filestore_tier
  project  = var.project_id
  
  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "shared"
    
    nfs_export_options {
      ip_ranges   = ["10.0.0.0/8"]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }
  
  networks {
    network = var.network_id
    modes   = ["MODE_IPV4"]
  }
  
  labels = var.labels
}

# IAM bindings for storage access
resource "google_storage_bucket_iam_member" "mlflow_artifacts_access" {
  bucket = google_storage_bucket.mlflow_artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.mlflow_service_account}"
  
  depends_on = [google_storage_bucket.mlflow_artifacts]
}

resource "google_storage_bucket_iam_member" "notebooks_access" {
  bucket = google_storage_bucket.notebooks.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.jupyter_service_account}"
  
  depends_on = [google_storage_bucket.notebooks]
}

resource "google_storage_bucket_iam_member" "datasets_access" {
  for_each = toset([
    var.jupyter_service_account,
    var.ray_service_account
  ])
  
  bucket = google_storage_bucket.datasets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${each.value}"
  
  depends_on = [google_storage_bucket.datasets]
}

resource "google_storage_bucket_iam_member" "models_access" {
  for_each = toset([
    var.mlflow_service_account,
    var.ray_service_account
  ])
  
  bucket = google_storage_bucket.models.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value}"
  
  depends_on = [google_storage_bucket.models]
}
