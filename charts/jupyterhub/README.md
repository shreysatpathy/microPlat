# JupyterHub Wrapper Chart

This chart references the upstream [JupyterHub Helm chart](https://jupyterhub.github.io/helm-chart/) and pins a version compatible with our platform.

Why a wrapper?
* Keep our own `values.yaml` under version control.
* Add defaults (Longhorn StorageClass, Ray env variables, image registry path).
* Allow other charts to depend on a stable name (`jupyterhub-platform`).

## Usage
```bash
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm dependency update charts/jupyterhub
helm upgrade --install jupyterhub charts/jupyterhub \
  --namespace ml-dev --create-namespace \
  --values charts/jupyterhub/values.yaml
```

> NOTE: Ensure `proxy.secretToken` is set to a 32-byte random string before first deploy. Generate with:
> `openssl rand -hex 32` and patch the value or set with `--set proxy.secretToken=$(openssl rand -hex 32)`
