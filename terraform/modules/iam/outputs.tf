output "service_account_emails" {
  description = "Service account emails"
  value = {
    mlflow     = google_service_account.mlflow.email
    jupyterhub = google_service_account.jupyterhub.email
    ray        = google_service_account.ray.email
    monitoring = google_service_account.monitoring.email
    argocd     = google_service_account.argocd.email
  }
}

output "service_account_ids" {
  description = "Service account IDs"
  value = {
    mlflow     = google_service_account.mlflow.id
    jupyterhub = google_service_account.jupyterhub.id
    ray        = google_service_account.ray.id
    monitoring = google_service_account.monitoring.id
    argocd     = google_service_account.argocd.id
  }
}

output "workload_identity_bindings" {
  description = "Workload Identity bindings"
  value = {
    mlflow = {
      gsa_email = google_service_account.mlflow.email
      ksa_namespace = "mlflow"
      ksa_name = "mlflow"
    }
    jupyterhub = {
      gsa_email = google_service_account.jupyterhub.email
      ksa_namespace = "jupyterhub"
      ksa_names = ["hub", "user-scheduler"]
    }
    ray = {
      gsa_email = google_service_account.ray.email
      ksa_namespace = "ray-system"
      ksa_names = ["ray-head", "ray-worker"]
    }
    monitoring = {
      gsa_email = google_service_account.monitoring.email
      ksa_namespace = "monitoring"
      ksa_names = ["prometheus-kube-prometheus-prometheus", "grafana"]
    }
    argocd = {
      gsa_email = google_service_account.argocd.email
      ksa_namespace = "argocd"
      ksa_names = ["argocd-application-controller", "argocd-server"]
    }
  }
}
