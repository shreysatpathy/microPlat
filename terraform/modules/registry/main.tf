# Artifact Registry module for ML Platform

# Docker repository for ML platform images
resource "google_artifact_registry_repository" "ml_platform" {
  location      = var.region
  repository_id = "${var.name_prefix}-images"
  description   = "Docker repository for ML platform images"
  format        = "DOCKER"
  project       = var.project_id
  
  labels = var.labels
}

# Python repository for custom packages
resource "google_artifact_registry_repository" "python_packages" {
  location      = var.region
  repository_id = "${var.name_prefix}-python"
  description   = "Python repository for custom ML packages"
  format        = "PYTHON"
  project       = var.project_id
  
  labels = var.labels
}

# IAM bindings for Artifact Registry access
resource "google_artifact_registry_repository_iam_member" "docker_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.ml_platform.location
  repository = google_artifact_registry_repository.ml_platform.name
  role       = "roles/artifactregistry.reader"
  member     = "allUsers"
}

resource "google_artifact_registry_repository_iam_member" "docker_writer" {
  for_each = toset([
    "serviceAccount:${var.ci_service_account}",
    "serviceAccount:${var.developer_service_account}"
  ])
  
  project    = var.project_id
  location   = google_artifact_registry_repository.ml_platform.location
  repository = google_artifact_registry_repository.ml_platform.name
  role       = "roles/artifactregistry.writer"
  member     = each.value
}

resource "google_artifact_registry_repository_iam_member" "python_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.python_packages.location
  repository = google_artifact_registry_repository.python_packages.name
  role       = "roles/artifactregistry.reader"
  member     = "allUsers"
}

resource "google_artifact_registry_repository_iam_member" "python_writer" {
  for_each = toset([
    "serviceAccount:${var.ci_service_account}",
    "serviceAccount:${var.developer_service_account}"
  ])
  
  project    = var.project_id
  location   = google_artifact_registry_repository.python_packages.location
  repository = google_artifact_registry_repository.python_packages.name
  role       = "roles/artifactregistry.writer"
  member     = each.value
}
