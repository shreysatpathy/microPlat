#!/usr/bin/env bash
# Bootstraps a local Minikube cluster with Ingress, Argo CD, and an Argo CD
# Application for JupyterHub.
#
# Usage:
#   ./bootstrap/cluster-bootstrap.sh [GIT_REPO_URL] [REVISION]
#
# Example:
#   ./bootstrap/cluster-bootstrap.sh https://github.com/yourname/ml-platform.git main
#
# If you omit arguments, sensible defaults are used.

set -euo pipefail

REPO_URL="${1:-https://github.com/REPO_OWNER/ml-platform.git}"
REVISION="${2:-main}"
NAMESPACE_ARGOCD="argocd"

# 1. Start Minikube (Docker driver assumed)
if ! minikube status >/dev/null 2>&1; then
  echo "[+] Starting Minikube cluster..."
  minikube start --driver=docker --memory=8192 --cpus=4
else
  echo "[=] Minikube already running"
fi

# 2. Enable ingress addon
if ! minikube addons list | grep -q 'ingress.*enabled'; then
  echo "[+] Enabling Ingress addon"
  minikube addons enable ingress
fi

# 3. Install Argo CD
if ! kubectl get ns ${NAMESPACE_ARGOCD} >/dev/null 2>&1; then
  echo "[+] Installing Argo CD"
  kubectl create namespace ${NAMESPACE_ARGOCD}
  kubectl apply -n ${NAMESPACE_ARGOCD} -f \
    https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi

# Wait for Argo CD server to be ready
echo "[~] Waiting for Argo CD server deployment to roll out..."
kubectl -n ${NAMESPACE_ARGOCD} rollout status deploy/argocd-server --timeout=5m

# 4. Apply Argo CD Applications (parameterised repo URL & revision)
export REPO_URL
export REVISION

apply_with_substitution() {
  envsubst < "$1" | kubectl apply -n ${NAMESPACE_ARGOCD} -f -
}

echo "[+] Applying Argo CD application: jupyterhub"
apply_with_substitution manifests/applications/jupyterhub.yaml

echo "[✔] Cluster bootstrap complete. Access Argo CD UI via:"
echo "    kubectl -n argocd port-forward svc/argocd-server 8080:443"
initial_pw=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Login: admin / ${initial_pw}"
