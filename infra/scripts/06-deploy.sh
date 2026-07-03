#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

require aws
require kubectl
require helm

: "${APP_HOSTNAME:?Set APP_HOSTNAME, for example app.example.com}"

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-$(ecr_uri)}"
CERTIFICATE_ARN="${CERTIFICATE_ARN:-}"
APP_ROLE_ARN="${APP_ROLE_ARN:-}"

if [[ -z "$CERTIFICATE_ARN" ]]; then
  CERTIFICATE_ARN="$(aws acm list-certificates \
    --region "$AWS_REGION" \
    --certificate-statuses ISSUED \
    --query "CertificateSummaryList[?DomainName=='${APP_HOSTNAME}'].CertificateArn | [0]" \
    --output text)"
  [[ "$CERTIFICATE_ARN" == "None" ]] && CERTIFICATE_ARN=""
fi

VALUES_FILE="$GENERATED_DIR/deploy-values.yaml"
cat > "$VALUES_FILE" <<YAML
image:
  repository: "${IMAGE_REPOSITORY}"
  tag: "${IMAGE_TAG}"
config:
  appEnv: "eks"
  appMessage: "deployed from Helm on EKS"
ingress:
  certificateArn: "${CERTIFICATE_ARN}"
  hosts:
    - host: "${APP_HOSTNAME}"
      paths:
        - path: /
          pathType: Prefix
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "${APP_ROLE_ARN}"
YAML

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm lint charts/interview-app -f "$VALUES_FILE"
helm upgrade --install "$HELM_RELEASE" charts/interview-app \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE" \
  --wait \
  --timeout 10m

echo
kubectl get deploy,sts,ds,svc,pvc,hpa,ingress -n "$NAMESPACE"
echo
echo "ALB hostname:"
kubectl get ingress "$HELM_RELEASE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
