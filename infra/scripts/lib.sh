#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATED_DIR="$ROOT_DIR/.generated"
mkdir -p "$GENERATED_DIR"

: "${AWS_REGION:=ap-south-1}"
: "${CLUSTER_NAME:=interview-eks}"
: "${K8S_VERSION:=1.34}"
: "${NAMESPACE:=interview}"
: "${HELM_RELEASE:=interview-app}"
: "${ECR_REPOSITORY:=interview-app}"
: "${IMAGE_TAG:=manual-$(date +%Y%m%d%H%M)}"
: "${DOCKER_PLATFORM:=linux/amd64}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

account_id() {
  aws sts get-caller-identity --query Account --output text
}

render_template() {
  local input="$1"
  local output="$2"
  local account="${AWS_ACCOUNT_ID:-$(account_id)}"

  sed \
    -e "s|__AWS_REGION__|${AWS_REGION}|g" \
    -e "s|__AWS_ACCOUNT_ID__|${account}|g" \
    -e "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" \
    -e "s|__K8S_VERSION__|${K8S_VERSION}|g" \
    -e "s|__NAMESPACE__|${NAMESPACE}|g" \
    -e "s|__GITHUB_OWNER__|${GITHUB_OWNER:-your-github-user-or-org}|g" \
    -e "s|__GITHUB_REPO__|${GITHUB_REPO:-eks-interview-lab}|g" \
    -e "s|__GITHUB_BRANCH__|${GITHUB_BRANCH:-main}|g" \
    -e "s|__ECR_REPOSITORY__|${ECR_REPOSITORY}|g" \
    -e "s|__IRSA_BUCKET_NAME__|${IRSA_BUCKET_NAME:-${account}-${AWS_REGION}-${CLUSTER_NAME}-irsa-demo}|g" \
    "$input" > "$output"
}

ecr_uri() {
  local account="${AWS_ACCOUNT_ID:-$(account_id)}"
  echo "${account}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
}

hosted_zone_id_for_domain() {
  local domain="$1"
  local zone_id
  zone_id="$(aws route53 list-hosted-zones-by-name \
    --dns-name "${domain}." \
    --query "HostedZones[?Name=='${domain}.'].Id | [0]" \
    --output text)"
  if [[ "$zone_id" == "None" || -z "$zone_id" ]]; then
    return 1
  fi
  echo "${zone_id##*/}"
}
