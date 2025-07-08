# IAM module for ML Platform service accounts and workload identity

# MLflow service account
resource "google_service_account" "mlflow" {
  account_id   = "${var.name_prefix}-mlflow"
  display_name = "MLflow Service Account"
  description  = "Service account for MLflow tracking server"
  project      = var.project_id
}

# JupyterHub service account
resource "google_service_account" "jupyterhub" {
  account_id   = "${var.name_prefix}-jupyterhub"
  display_name = "JupyterHub Service Account"
  description  = "Service account for JupyterHub"
  project      = var.project_id
}

# Ray service account
resource "google_service_account" "ray" {
  account_id   = "${var.name_prefix}-ray"
  display_name = "Ray Service Account"
  description  = "Service account for Ray cluster"
  project      = var.project_id
}

# Monitoring service account
resource "google_service_account" "monitoring" {
  account_id   = "${var.name_prefix}-monitoring"
  display_name = "Monitoring Service Account"
  description  = "Service account for monitoring stack"
  project      = var.project_id
}

# ArgoCD service account
resource "google_service_account" "argocd" {
  account_id   = "${var.name_prefix}-argocd"
  display_name = "ArgoCD Service Account"
  description  = "Service account for ArgoCD"
  project      = var.project_id
}

# IAM roles for MLflow
resource "google_project_iam_member" "mlflow_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.mlflow.email}"
}

resource "google_project_iam_member" "mlflow_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.mlflow.email}"
}

# IAM roles for JupyterHub
resource "google_project_iam_member" "jupyterhub_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.jupyterhub.email}"
}

resource "google_project_iam_member" "jupyterhub_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.jupyterhub.email}"
}

# IAM roles for Ray
resource "google_project_iam_member" "ray_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.ray.email}"
}

resource "google_project_iam_member" "ray_compute" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.ray.email}"
}

resource "google_project_iam_member" "ray_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.ray.email}"
}

# IAM roles for Monitoring
resource "google_project_iam_member" "monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.monitoring.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.monitoring.email}"
}

resource "google_project_iam_member" "monitoring_logging" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.monitoring.email}"
}

# IAM roles for ArgoCD
resource "google_project_iam_member" "argocd_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.argocd.email}"
}

resource "google_project_iam_member" "argocd_source_reader" {
  project = var.project_id
  role    = "roles/source.reader"
  member  = "serviceAccount:${google_service_account.argocd.email}"
}

# Workload Identity bindings
resource "google_service_account_iam_binding" "mlflow_workload_identity" {
  service_account_id = google_service_account.mlflow.name
  role               = "roles/iam.workloadIdentityUser"
  
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[mlflow/mlflow]"
  ]
}

resource "google_service_account_iam_binding" "jupyterhub_workload_identity" {
  service_account_id = google_service_account.jupyterhub.name
  role               = "roles/iam.workloadIdentityUser"
  
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[jupyterhub/hub]",
    "serviceAccount:${var.project_id}.svc.id.goog[jupyterhub/user-scheduler]"
  ]
}

resource "google_service_account_iam_binding" "ray_workload_identity" {
  service_account_id = google_service_account.ray.name
  role               = "roles/iam.workloadIdentityUser"
  
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[ray-system/ray-head]",
    "serviceAccount:${var.project_id}.svc.id.goog[ray-system/ray-worker]"
  ]
}

resource "google_service_account_iam_binding" "monitoring_workload_identity" {
  service_account_id = google_service_account.monitoring.name
  role               = "roles/iam.workloadIdentityUser"
  
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[monitoring/prometheus-kube-prometheus-prometheus]",
    "serviceAccount:${var.project_id}.svc.id.goog[monitoring/grafana]"
  ]
}

resource "google_service_account_iam_binding" "argocd_workload_identity" {
  service_account_id = google_service_account.argocd.name
  role               = "roles/iam.workloadIdentityUser"
  
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-application-controller]",
    "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-server]"
  ]
}
