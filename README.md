# ML Platform on Kubernetes

This repository contains a **machine-learning experimentation and deployment platform** that can run locally on Minikube and scale to any managed Kubernetes service (EKS, GKE, AKS, OpenShift, etc.) using GitOps.

Key components:
* **Argo CD** – GitOps engine that syncs Kubernetes manifests/Helm charts from this repo.
* **JupyterHub** – Spawns per-user Jupyter notebooks with a mounted shared PVC.
* **Ray** – Distributed compute for training, hyper-parameter tuning (Ray Tune), and online serving (Ray Serve).
* **MLflow** – Experiment tracking and artifact storage.
* **Longhorn / NFS** – Shared POSIX-like persistent storage (local). Swap for EFS/Filestore in the cloud.
* **MinIO** – S3-compatible object store for datasets and model artifacts (local).
* **Prometheus + Grafana + Loki** – Observability stack.

See `plan.md` for the full design document and milestones.

---

## Prerequisites (Windows + WSL 2)

The platform is built and tested on **Windows 10/11** with an Ubuntu WSL 2 distro. Ensure the following tools are installed **inside WSL**, not on the Windows host:

1. **Docker Engine** (no Docker Desktop required)
```bash
sudo apt-get remove docker docker-engine docker.io containerd runc -y
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER && newgrp docker
```

2. **kubectl**
```bash
curl -LO https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

3. **Helm**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

4. **Minikube** (Docker driver)
```bash
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube && sudo mv minikube /usr/local/bin/
minikube start --driver=docker --memory=8192 --cpus=4
```

Quick validation:
```bash
kubectl get nodes
minikube kubectl -- get pods -A
```

Once Minikube is up, enable Ingress:
```bash
minikube addons enable ingress
```

You’re now ready to apply the manifests and run the ML platform locally.
