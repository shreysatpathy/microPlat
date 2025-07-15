#!/bin/bash
set -e

# Variables
NOTEBOOK_IMAGE="microplat/notebook:latest"
DOCKER_DIR="$(dirname "$(dirname "$0")")/docker/notebook"

echo "===== Building Custom Notebook Image ====="
echo "Image: $NOTEBOOK_IMAGE"
echo "Directory: $DOCKER_DIR"

# Build the notebook image
docker build -t $NOTEBOOK_IMAGE $DOCKER_DIR

echo "===== Image Built Successfully ====="
echo "You can push this image to your registry with:"
echo "docker push $NOTEBOOK_IMAGE"

echo ""
echo "To use a custom registry, first retag with:"
echo "docker tag $NOTEBOOK_IMAGE YOUR_REGISTRY/$NOTEBOOK_IMAGE"
echo "Then push with:"
echo "docker push YOUR_REGISTRY/$NOTEBOOK_IMAGE"
echo ""
echo "Don't forget to update the image name in charts/jupyterhub/values.yaml"
