#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

require aws

: "${GITHUB_OWNER:?Set GITHUB_OWNER}"
: "${GITHUB_REPO:?Set GITHUB_REPO}"
: "${GITHUB_BRANCH:=main}"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(account_id)}"
ROLE_NAME="${CLUSTER_NAME}-github-actions-deployer"
POLICY_NAME="${CLUSTER_NAME}-github-actions-deploy-policy"
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

TRUST_FILE="$GENERATED_DIR/github-actions-trust-policy.json"
POLICY_FILE="$GENERATED_DIR/github-actions-policy.json"
render_template infra/iam/github-actions-trust-policy-template.json "$TRUST_FILE"
render_template infra/iam/github-actions-policy-template.json "$POLICY_FILE"

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${TRUST_FILE}" >/dev/null
else
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "file://${TRUST_FILE}" >/dev/null
fi

POLICY_ARN="$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn | [0]" \
  --output text)"
if [[ "$POLICY_ARN" == "None" || -z "$POLICY_ARN" ]]; then
  POLICY_ARN="$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://${POLICY_FILE}" \
    --query Policy.Arn \
    --output text)"
else
  CURRENT_VERSION="$(aws iam get-policy --policy-arn "$POLICY_ARN" --query "Policy.DefaultVersionId" --output text)"
  VERSION_COUNT="$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query "length(Versions)" --output text)"
  if [[ "$VERSION_COUNT" -ge 5 ]]; then
    OLD_VERSION="$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" \
      --query "Versions[?IsDefaultVersion==\`false\`] | sort_by(@,&CreateDate)[0].VersionId" \
      --output text)"
    aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$OLD_VERSION"
  fi
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document "file://${POLICY_FILE}" \
    --set-as-default >/dev/null
fi

aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" >/dev/null

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1; then
  aws ecr create-repository \
    --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY" \
    --image-scanning-configuration scanOnPush=true >/dev/null
fi

if ! aws eks list-access-entries \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --query "accessEntries[?@=='${ROLE_ARN}'] | [0]" \
  --output text | grep -q "$ROLE_ARN"; then
  aws eks create-access-entry \
    --region "$AWS_REGION" \
    --cluster-name "$CLUSTER_NAME" \
    --principal-arn "$ROLE_ARN" \
    --type STANDARD >/dev/null
fi

aws eks associate-access-policy \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$ROLE_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces="$NAMESPACE" >/dev/null || true

echo
echo "Add this to .env and to GitHub repository variable AWS_ROLE_ARN:"
echo "export GITHUB_ACTIONS_ROLE_ARN=\"${ROLE_ARN}\""
echo
echo "Recommended GitHub repository variables:"
echo "AWS_ROLE_ARN=${ROLE_ARN}"
echo "AWS_REGION=${AWS_REGION}"
echo "CLUSTER_NAME=${CLUSTER_NAME}"
echo "NAMESPACE=${NAMESPACE}"
echo "HELM_RELEASE=${HELM_RELEASE}"
echo "ECR_REPOSITORY=${ECR_REPOSITORY}"
echo "APP_HOSTNAME=${APP_HOSTNAME:-app.example.com}"
echo "CERTIFICATE_ARN=${CERTIFICATE_ARN:-}"
echo "APP_ROLE_ARN=${APP_ROLE_ARN:-}"
