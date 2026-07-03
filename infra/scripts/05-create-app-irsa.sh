#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

require aws
require eksctl
require kubectl

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(account_id)}"
RAW_BUCKET="${IRSA_BUCKET_NAME:-${AWS_ACCOUNT_ID}-${AWS_REGION}-${CLUSTER_NAME}-irsa-demo}"
IRSA_BUCKET_NAME="$(echo "$RAW_BUCKET" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-' | cut -c1-63)"
POLICY_NAME="${CLUSTER_NAME}-interview-app-s3-policy"
ROLE_NAME="${CLUSTER_NAME}-interview-app-irsa"
SERVICE_ACCOUNT_NAME="interview-app"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if ! aws s3api head-bucket --bucket "$IRSA_BUCKET_NAME" >/dev/null 2>&1; then
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$IRSA_BUCKET_NAME" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "$IRSA_BUCKET_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
  aws s3api put-public-access-block \
    --bucket "$IRSA_BUCKET_NAME" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

POLICY_FILE="$GENERATED_DIR/app-s3-policy.json"
IRSA_BUCKET_NAME="$IRSA_BUCKET_NAME" render_template infra/iam/app-s3-policy-template.json "$POLICY_FILE"

POLICY_ARN="$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn | [0]" \
  --output text)"
if [[ "$POLICY_ARN" == "None" || -z "$POLICY_ARN" ]]; then
  POLICY_ARN="$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://${POLICY_FILE}" \
    --query Policy.Arn \
    --output text)"
fi

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --namespace "$NAMESPACE" \
  --name "$SERVICE_ACCOUNT_NAME" \
  --role-name "$ROLE_NAME" \
  --role-only \
  --attach-policy-arn "$POLICY_ARN" \
  --approve \
  --override-existing-serviceaccounts

APP_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
{
  echo "export IRSA_BUCKET_NAME=\"${IRSA_BUCKET_NAME}\""
  echo "export APP_ROLE_ARN=\"${APP_ROLE_ARN}\""
} > "$GENERATED_DIR/app-irsa.env"

echo
echo "Add these to .env:"
cat "$GENERATED_DIR/app-irsa.env"
