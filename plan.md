# Machine-Learning Experimentation & Deployment Platform – Project Plan

> Last updated: 2025-07-01

---

## 1  High-Level Architecture

| Area                | Chosen Component (Kubernetes-native) |
|---------------------|---------------------------------------|
| **Source of Truth** | Git repository (manifests, Helm charts, code, notebooks) |
| **GitOps Engine**   | Argo CD (or Flux) |
| **Container Registry** | ghcr.io (swap for ECR / GCR / ACR in cloud) |
| **Shared Filesystem** | Longhorn or NFS on Minikube → EFS/Filestore/Azure Files in cloud |
| **Object Storage**  | MinIO (S3-compatible) locally → AWS S3 / GCS in cloud |
| **Experiment Tracking** | MLflow (optional but recommended) |
| **Interactive Workbench** | JupyterHub (spawns user notebooks, mounts PVC) |
| **Distributed Compute** | Ray Operator → RayCluster CRD |
| **Hyper-param Tuning** | Ray Tune inside RayCluster |
| **Model Serving**   | Ray Serve deployments behind K8s Service / Ingress |
| **Observability**   | kube-prometheus-stack, Grafana, Loki |
| **Secrets**         | SealedSecrets or External-Secrets Operator |
| **CI**              | GitHub Actions (build images, update Helm values, PR) |

---

## 2  Repository Layout
```
ml-platform/
├── charts/               # Helm charts & Kustomize bases
│   ├── jupyterhub/
│   ├── ray-cluster/
│   ├── ray-serve/
│   └── mlflow/
├── manifests/            # K8s YAML overlays (kustomize)
├── docker/               # Dockerfiles for notebook, trainer & serve images
├── notebooks/            # Example notebooks
├── experiments/          # MLflow runs / Ray Tune results
└── .github/
    └── workflows/        # CI pipelines
```

---

## 3  GitOps Workflow
1. Developer pushes code or chart change.
2. GitHub Actions builds image, pushes to registry, updates image tag in the appropriate Helm `values.yaml`, and opens a PR.
3. Merge to `main` ⇒ Argo CD syncs the target cluster automatically.
4. Rollbacks are simple `git revert`s; promotion between clusters is handled by branch or directory-based environments.

---

## 4  Persistent Storage Strategy
* **Local (Minikube):** enable Longhorn or NFS provisioner; mount the same PVC in Jupyter, Ray, and MLflow pods.
* **Cloud:** migrate to EFS (EKS), Filestore (GKE), or Azure Files; object data lives in S3/GCS, accessed via SDK or mounted with `s3fs`.

---

## 5  Interactive Notebooks
* Deploy JupyterHub with official Helm chart.
* Configure `hub.extraVolumes` & `singleuser.extraVolumes` to mount the shared PVC.
* Use a custom Docker image (`docker/notebook.Dockerfile`) containing the common ML stack + Ray client libs.

---

## 6  Ray Cluster & Serve
* Install Ray Operator via Helm.
* Define `RayCluster` CRD: head + worker groups with resource requests (CPU/GPU optional).
* Use `ray.init(address="auto")` inside notebooks or batch jobs.
* Model serving:
  1. Build a serving image with the model and a FastAPI handler.
  2. Apply `RayService` CRD (Ray 2.x) so the operator manages rollout & autoscaling.
  3. Expose with a Kubernetes Service and Ingress (NGINX/Traefik).

---

## 7  CI/CD Details
* Matrix build in `.github/workflows/build-push.yml` over `notebook`, `trainer`, `serve` images.
* Use `docker buildx` to build, `docker push` to registry.
* Patch chart `values.yaml` using `yq`, commit, and push back to the repo.

---

## 8  Security & Multi-tenancy
* Namespaces per environment (`ml-dev`, `ml-prod`).
* NetworkPolicies to isolate Ray clusters.
* JupyterHub user pods run as non-root; PVCs provided via RWX StorageClass.
* Store secrets encrypted with SealedSecrets.

---

## 9  Observability
* Deploy `kube-prometheus-stack` Helm chart (Prometheus, Alertmanager, Grafana).
* Enable Ray dashboard agent – Prometheus scrapes metrics.
* Central logging via Loki and Grafana Loki datasource.

---

## 10  Roll-out Milestones
| Milestone | Deliverable |
|-----------|-------------|
| M0 | Repo skeleton, Minikube cluster, Argo CD installed |
| M1 | Persistent storage (Longhorn/NFS) + JupyterHub mounting PVC |
| M2 | Ray Operator + sample RayCluster; notebook connection validated |
| M3 | MLflow tracking + MinIO artifact store |
| M4 | Ray Tune run from notebook; results tracked in MLflow |
| M5 | Ray Serve endpoint behind Ingress with autoscaling demo |
| M6 | CI pipeline (GitHub Actions) building images & updating Helm charts |
| M7 | Observability stack & alerting rules |
| M8 | Port manifests to managed Kubernetes (EKS/GKE/AKS) |

---

## 11  Immediate Next Steps
1. **Scaffold repository** directories & placeholder files (this commit).
2. Add `.gitignore`, basic `README.md`.
3. Generate empty Helm charts using `helm create` (manual step or commit skeleton directories).
4. Provide stub GitHub Actions workflow.
5. Commit & push → cluster bootstrap (Argo CD install) can follow.
