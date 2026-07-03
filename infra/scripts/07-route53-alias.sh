#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

require aws
require kubectl

: "${DOMAIN_NAME:?Set DOMAIN_NAME}"
: "${APP_HOSTNAME:?Set APP_HOSTNAME}"

ZONE_ID="$(hosted_zone_id_for_domain "$DOMAIN_NAME")"
ALB_DNS="$(kubectl get ingress "$HELM_RELEASE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

if [[ -z "$ALB_DNS" ]]; then
  echo "Ingress has no ALB address yet. Wait a minute and retry."
  exit 1
fi

ALB_ZONE_ID="$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}'].CanonicalHostedZoneId | [0]" \
  --output text)"

CHANGE_FILE="$GENERATED_DIR/app-alias-change.json"
cat > "$CHANGE_FILE" <<JSON
{
  "Comment": "Alias ${APP_HOSTNAME} to EKS ALB",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${APP_HOSTNAME}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_ZONE_ID}",
          "DNSName": "${ALB_DNS}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
JSON

aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "file://${CHANGE_FILE}" >/dev/null

echo "Created/updated Route 53 alias:"
echo "https://${APP_HOSTNAME}"
