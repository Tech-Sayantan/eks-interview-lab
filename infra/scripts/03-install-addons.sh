#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

require aws
require eksctl
require kubectl
require helm
require curl

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(account_id)}"

echo "Enabling Amazon VPC CNI NetworkPolicy support"
aws eks update-addon \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name vpc-cni \
  --resolve-conflicts OVERWRITE \
  --configuration-values '{"enableNetworkPolicy":"true","nodeAgent":{"healthProbeBindAddr":"8163","metricsBindAddr":"8162"}}' >/dev/null || \
  echo "VPC CNI may already be configured or updating; continuing."
aws eks wait addon-active \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name vpc-cni || true
kubectl rollout status daemonset/aws-node -n kube-system --timeout=180s || true

echo
echo "Installing/updating metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo
echo "Installing EBS CSI driver with IRSA"
EBS_ROLE_NAME="${CLUSTER_NAME}-AmazonEKS_EBS_CSI_DriverRole"
eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --role-name "$EBS_ROLE_NAME" \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2 \
  --approve \
  --override-existing-serviceaccounts

EBS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EBS_ROLE_NAME}"
if aws eks describe-addon --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name aws-ebs-csi-driver >/dev/null 2>&1; then
  aws eks update-addon \
    --region "$AWS_REGION" \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "$EBS_ROLE_ARN" \
    --resolve-conflicts OVERWRITE >/dev/null || true
else
  aws eks create-addon \
    --region "$AWS_REGION" \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "$EBS_ROLE_ARN" \
    --resolve-conflicts OVERWRITE >/dev/null
fi

echo
echo "Installing AWS Load Balancer Controller with IRSA"
LBC_POLICY_NAME="${CLUSTER_NAME}-AWSLoadBalancerControllerIAMPolicy"
LBC_POLICY_ARN="$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='${LBC_POLICY_NAME}'].Arn | [0]" \
  --output text)"

if [[ "$LBC_POLICY_ARN" == "None" || -z "$LBC_POLICY_ARN" ]]; then
  LBC_POLICY_FILE="$GENERATED_DIR/aws-load-balancer-controller-iam-policy.json"
  curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json \
    -o "$LBC_POLICY_FILE"
  LBC_POLICY_ARN="$(aws iam create-policy \
    --policy-name "$LBC_POLICY_NAME" \
    --policy-document "file://${LBC_POLICY_FILE}" \
    --query Policy.Arn \
    --output text)"
fi

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name "${CLUSTER_NAME}-AmazonEKSLoadBalancerControllerRole" \
  --attach-policy-arn "$LBC_POLICY_ARN" \
  --approve \
  --override-existing-serviceaccounts

helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$(aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --query "cluster.resourcesVpcConfig.vpcId" --output text)" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

echo
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s || true
kubectl get pods -n kube-system
