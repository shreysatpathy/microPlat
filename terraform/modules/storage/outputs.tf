output "gcs_buckets" {
  description = "Created GCS bucket names"
  value = {
    mlflow_artifacts = google_storage_bucket.mlflow_artifacts.name
    notebooks        = google_storage_bucket.notebooks.name
    datasets         = google_storage_bucket.datasets.name
    models           = google_storage_bucket.models.name
  }
}

output "gcs_bucket_urls" {
  description = "GCS bucket URLs"
  value = {
    mlflow_artifacts = google_storage_bucket.mlflow_artifacts.url
    notebooks        = google_storage_bucket.notebooks.url
    datasets         = google_storage_bucket.datasets.url
    models           = google_storage_bucket.models.url
  }
}

output "filestore_instance" {
  description = "Filestore instance details"
  value = {
    name       = google_filestore_instance.shared_storage.name
    ip_address = google_filestore_instance.shared_storage.networks[0].ip_addresses[0]
    file_share = google_filestore_instance.shared_storage.file_shares[0].name
    capacity   = google_filestore_instance.shared_storage.file_shares[0].capacity_gb
  }
}

output "filestore_mount_target" {
  description = "Filestore NFS mount target"
  value = "${google_filestore_instance.shared_storage.networks[0].ip_addresses[0]}:/${google_filestore_instance.shared_storage.file_shares[0].name}"
}
