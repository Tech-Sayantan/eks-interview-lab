#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

for tool in aws eksctl kubectl helm docker curl sed; do
  require "$tool"
done

echo "AWS identity:"
aws sts get-caller-identity --output table

echo
echo "Tool versions:"
aws --version
eksctl version
kubectl version --client=true
helm version --short
docker version --format '{{.Client.Version}}'

echo
echo "Good. Next: copy infra/scripts/env.example to .env, edit it, then run source .env"
