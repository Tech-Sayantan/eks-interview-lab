#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source infra/scripts/lib.sh

echo "Core objects:"
kubectl get pods,deploy,rs,sts,ds,svc,ep,pvc,hpa,ingress -n "$NAMESPACE" -o wide

echo
echo "Storage:"
kubectl get storageclass,pv,pvc -A

echo
echo "Describe app pod events:"
APP_POD="$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/instance="$HELM_RELEASE",app.kubernetes.io/name=interview-app -o jsonpath='{.items[0].metadata.name}')"
kubectl describe pod -n "$NAMESPACE" "$APP_POD" | sed -n '/Events:/,$p'

echo
echo "Test service inside cluster:"
kubectl run curl-test -n "$NAMESPACE" --rm -i --restart=Never --image=public.ecr.aws/docker/library/curlimages/curl:8.10.1 -- \
  curl -s "http://${HELM_RELEASE}.${NAMESPACE}.svc.cluster.local/redis/incr"

echo
echo "IRSA identity from app:"
kubectl run curl-irsa -n "$NAMESPACE" --rm -i --restart=Never --image=public.ecr.aws/docker/library/curlimages/curl:8.10.1 -- \
  curl -s "http://${HELM_RELEASE}.${NAMESPACE}.svc.cluster.local/aws/identity"

echo
echo "To trigger HPA manually:"
echo "kubectl run load -n ${NAMESPACE} --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://${HELM_RELEASE}.${NAMESPACE}.svc.cluster.local/burn?seconds=3; done'"
echo "kubectl get hpa -n ${NAMESPACE} -w"
