#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

require aws
require eksctl
require kubectl

CLUSTER_FILE="$GENERATED_DIR/cluster.yaml"
render_template infra/eksctl/cluster-template.yaml "$CLUSTER_FILE"

if aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "Cluster ${CLUSTER_NAME} already exists. Skipping creation."
else
  echo "Creating EKS cluster from ${CLUSTER_FILE}"
  eksctl create cluster -f "$CLUSTER_FILE"
fi

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl get nodes -o wide
