#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

require aws
require docker

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(account_id)}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-$(ecr_uri)}"

if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1; then
  aws ecr create-repository \
    --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY" \
    --image-scanning-configuration scanOnPush=true >/dev/null
fi

aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build --platform "$DOCKER_PLATFORM" -t "${IMAGE_REPOSITORY}:${IMAGE_TAG}" app
docker push "${IMAGE_REPOSITORY}:${IMAGE_TAG}"

echo
echo "Add these to .env:"
echo "export IMAGE_REPOSITORY=\"${IMAGE_REPOSITORY}\""
echo "export IMAGE_TAG=\"${IMAGE_TAG}\""
