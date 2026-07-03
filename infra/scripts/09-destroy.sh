#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

echo "This destroys the lab cluster and most chargeable resources."
echo "Cluster: ${CLUSTER_NAME}"
echo "Region:  ${AWS_REGION}"
echo
if [[ "${CONFIRM_DESTROY:-}" != "yes" ]]; then
  read -r -p "Type destroy-${CLUSTER_NAME} to continue: " answer
  if [[ "$answer" != "destroy-${CLUSTER_NAME}" ]]; then
    echo "Cancelled."
    exit 1
  fi
fi

ALB_DNS="$(kubectl get ingress "$HELM_RELEASE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

helm uninstall "$HELM_RELEASE" -n "$NAMESPACE" --wait --timeout 5m || true
kubectl delete pvc --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true || true

if [[ -n "$ALB_DNS" ]]; then
  echo "Waiting briefly for AWS Load Balancer Controller to delete ALB ${ALB_DNS}"
  for _ in {1..30}; do
    FOUND="$(aws elbv2 describe-load-balancers \
      --region "$AWS_REGION" \
      --query "LoadBalancers[?DNSName=='${ALB_DNS}'].DNSName | [0]" \
      --output text 2>/dev/null || true)"
    [[ "$FOUND" == "None" || -z "$FOUND" ]] && break
    sleep 20
  done
fi

eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait || true

if [[ "${DESTROY_ECR:-false}" == "true" ]]; then
  aws ecr delete-repository --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" --force || true
fi

if [[ "${DESTROY_S3:-false}" == "true" && -n "${IRSA_BUCKET_NAME:-}" ]]; then
  aws s3 rm "s3://${IRSA_BUCKET_NAME}" --recursive || true
  aws s3api delete-bucket --bucket "$IRSA_BUCKET_NAME" --region "$AWS_REGION" || true
fi

if [[ "${DESTROY_ACM:-false}" == "true" && -n "${CERTIFICATE_ARN:-}" ]]; then
  aws acm delete-certificate --region "$AWS_REGION" --certificate-arn "$CERTIFICATE_ARN" || true
fi

echo
echo "Done. Check these screens manually for leftovers:"
echo "- EC2 Load Balancers, Volumes, NAT Gateways"
echo "- EKS clusters"
echo "- CloudFormation stacks with prefix eksctl-${CLUSTER_NAME}"
echo "- Route 53 hosted zone and records, if you no longer need them"
