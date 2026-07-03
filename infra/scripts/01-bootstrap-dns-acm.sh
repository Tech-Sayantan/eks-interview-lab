#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

: "${DOMAIN_NAME:?Set DOMAIN_NAME, for example example.com}"
: "${APP_HOSTNAME:?Set APP_HOSTNAME, for example app.example.com}"

ZONE_ID="$(hosted_zone_id_for_domain "$DOMAIN_NAME" || true)"
if [[ -z "${ZONE_ID}" ]]; then
  echo "Creating Route 53 hosted zone for ${DOMAIN_NAME}"
  ZONE_ID="$(aws route53 create-hosted-zone \
    --name "$DOMAIN_NAME" \
    --caller-reference "${DOMAIN_NAME}-$(date +%s)" \
    --hosted-zone-config Comment="EKS interview lab zone" \
    --query "HostedZone.Id" \
    --output text)"
  ZONE_ID="${ZONE_ID##*/}"
else
  echo "Using existing hosted zone ${ZONE_ID} for ${DOMAIN_NAME}"
fi

echo
echo "Name servers for GoDaddy:"
aws route53 get-hosted-zone --id "$ZONE_ID" \
  --query "DelegationSet.NameServers" \
  --output text

echo
echo "In GoDaddy, replace the domain nameservers with the values above."
echo "DNS and ACM validation will not complete until delegation reaches the public DNS system."

CERT_ARN="${CERTIFICATE_ARN:-}"
if [[ -z "$CERT_ARN" ]]; then
  CERT_ARN="$(aws acm list-certificates \
    --region "$AWS_REGION" \
    --certificate-statuses PENDING_VALIDATION ISSUED \
    --query "CertificateSummaryList[?DomainName=='${APP_HOSTNAME}'].CertificateArn | [0]" \
    --output text)"
fi

if [[ "$CERT_ARN" == "None" || -z "$CERT_ARN" ]]; then
  echo "Requesting ACM certificate for ${APP_HOSTNAME}"
  CERT_ARN="$(aws acm request-certificate \
    --region "$AWS_REGION" \
    --domain-name "$APP_HOSTNAME" \
    --validation-method DNS \
    --query CertificateArn \
    --output text)"
fi

echo "Certificate ARN: ${CERT_ARN}"
sleep 8

RR_NAME="$(aws acm describe-certificate \
  --region "$AWS_REGION" \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord.Name" \
  --output text)"
RR_TYPE="$(aws acm describe-certificate \
  --region "$AWS_REGION" \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord.Type" \
  --output text)"
RR_VALUE="$(aws acm describe-certificate \
  --region "$AWS_REGION" \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord.Value" \
  --output text)"

if [[ "$RR_NAME" != "None" && "$RR_VALUE" != "None" ]]; then
  CHANGE_FILE="$GENERATED_DIR/acm-validation-change.json"
  cat > "$CHANGE_FILE" <<JSON
{
  "Comment": "ACM DNS validation for ${APP_HOSTNAME}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RR_NAME}",
        "Type": "${RR_TYPE}",
        "TTL": 60,
        "ResourceRecords": [{ "Value": "${RR_VALUE}" }]
      }
    }
  ]
}
JSON
  aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch "file://${CHANGE_FILE}" >/dev/null
  echo "Created ACM DNS validation record in Route 53."
fi

echo
echo "Checking certificate status for up to 10 minutes..."
for _ in {1..20}; do
  STATUS="$(aws acm describe-certificate \
    --region "$AWS_REGION" \
    --certificate-arn "$CERT_ARN" \
    --query "Certificate.Status" \
    --output text)"
  echo "ACM status: ${STATUS}"
  if [[ "$STATUS" == "ISSUED" ]]; then
    break
  fi
  sleep 30
done

echo
echo "Add this to .env:"
echo "export CERTIFICATE_ARN=\"${CERT_ARN}\""
