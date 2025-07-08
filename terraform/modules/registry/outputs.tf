output "repository_urls" {
  description = "Artifact Registry repository URLs"
  value = {
    docker = "${google_artifact_registry_repository.ml_platform.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ml_platform.name}"
    python = "${google_artifact_registry_repository.python_packages.location}-python.pkg.dev/${var.project_id}/${google_artifact_registry_repository.python_packages.name}"
  }
}

output "repository_names" {
  description = "Artifact Registry repository names"
  value = {
    docker = google_artifact_registry_repository.ml_platform.name
    python = google_artifact_registry_repository.python_packages.name
  }
}

output "docker_registry_url" {
  description = "Docker registry URL for image tags"
  value = "${google_artifact_registry_repository.ml_platform.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ml_platform.name}"
}
