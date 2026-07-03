# Troubleshooting Runbook

Use this order during live debugging:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
```

## Pod Pending

Likely causes:

- Not enough CPU/memory.
- PVC is Pending.
- Taints/tolerations mismatch.
- Node selector or affinity impossible.
- ResourceQuota blocks admission.

Commands:

```bash
kubectl describe pod <pod> -n interview
kubectl describe quota -n interview
kubectl get pvc -n interview
kubectl describe pvc <pvc> -n interview
```

## ImagePullBackOff

Likely causes:

- Wrong ECR repo or tag.
- Image built for wrong architecture.
- Node cannot authenticate or reach ECR.
- ECR repository policy/IAM issue.

Commands:

```bash
kubectl describe pod <pod> -n interview
aws ecr describe-images --repository-name interview-app --region ap-south-1
```

## CrashLoopBackOff

Likely causes:

- App exits.
- Missing env var.
- Bad command.
- Read-only filesystem issue.
- Port mismatch.

Commands:

```bash
kubectl logs <pod> -n interview
kubectl logs <pod> -n interview --previous
kubectl describe pod <pod> -n interview
```

## Readiness Fails

In this lab, `/readyz` checks Redis.

Commands:

```bash
kubectl get sts,pod,svc,endpoints -n interview
kubectl logs statefulset/interview-app-redis -n interview
kubectl run dns-test -n interview --rm -i --restart=Never --image=public.ecr.aws/docker/library/busybox:1.36 -- nslookup interview-app-redis
```

## PVC Pending

Likely causes:

- EBS CSI driver missing.
- EBS CSI IAM role lacks permission.
- StorageClass provisioner wrong.
- No suitable node/AZ because of `WaitForFirstConsumer`.

Commands:

```bash
kubectl get storageclass
kubectl get pods -n kube-system | grep ebs
kubectl describe pvc -n interview
kubectl logs -n kube-system deployment/ebs-csi-controller
```

## Ingress Has No Address

Likely causes:

- AWS Load Balancer Controller not running.
- IAM policy/trust issue.
- Ingress class wrong.
- Public subnets missing ELB tags.
- Certificate ARN wrong region.

Commands:

```bash
kubectl get ingress -n interview
kubectl describe ingress interview-app -n interview
kubectl logs -n kube-system deployment/aws-load-balancer-controller
aws elbv2 describe-load-balancers --region ap-south-1
```

## ALB Returns 503

Likely causes:

- Target group has no healthy targets.
- Readiness path failing.
- Service selector mismatch.
- Target port mismatch.
- Security group issue.

Commands:

```bash
kubectl get endpoints -n interview
kubectl describe targetgroupbinding -n interview
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

## HPA Shows Unknown

Likely causes:

- metrics-server not installed or not Ready.
- Pods do not have CPU requests.
- Metrics have not arrived yet.

Commands:

```bash
kubectl top nodes
kubectl top pods -n interview
kubectl describe hpa interview-app -n interview
```

## NetworkPolicy Does Nothing

Likely causes:

- CNI does not enforce NetworkPolicy.
- VPC CNI network policy support was not enabled.
- Pod labels do not match the policy selector.
- Traffic is allowed by another additive policy.

Commands:

```bash
kubectl get netpol -n interview
kubectl describe netpol interview-app-web -n interview
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl describe daemonset aws-node -n kube-system | grep -E 'enable-network-policy|aws-network-policy-agent' -A3
```

## NetworkPolicy Blocks Too Much

Likely causes:

- DNS egress missing.
- HTTPS egress missing for AWS APIs.
- Service port and target port mismatch.
- ALB target traffic not allowed.

Commands:

```bash
kubectl run net-test -n interview --rm -i --restart=Never --image=public.ecr.aws/docker/library/busybox:1.36 -- nslookup kubernetes.default
kubectl run curl-test -n interview --rm -i --restart=Never --image=public.ecr.aws/docker/library/curlimages/curl:8.10.1 -- curl -v http://interview-app/healthz
```

## IRSA AccessDenied

Likely causes:

- ServiceAccount annotation missing.
- Pod uses wrong service account.
- IAM trust policy `sub` does not match namespace/service account.
- IAM policy does not allow the action.
- OIDC provider missing.

Commands:

```bash
kubectl get sa interview-app -n interview -o yaml
kubectl exec -n interview deploy/interview-app -- env | grep AWS
kubectl run curl-irsa -n interview --rm -i --restart=Never --image=public.ecr.aws/docker/library/curlimages/curl:8.10.1 -- curl -s http://interview-app/aws/identity
```

## GitHub Actions OIDC AccessDenied

Likely causes:

- Missing `id-token: write`.
- AWS role trust policy repo/branch mismatch.
- GitHub variable `AWS_ROLE_ARN` missing.
- Pushed from a branch not allowed by trust policy.

Check:

```bash
aws iam get-role --role-name interview-eks-github-actions-deployer
```

## Cluster Delete Fails

Likely causes:

- ALB still exists.
- ENI still attached.
- EBS volume still bound.
- Security group dependency.
- CloudFormation stack waiting on node drain.

Fix:

```bash
helm uninstall interview-app -n interview --wait
kubectl delete pvc --all -n interview
aws elbv2 describe-load-balancers --region ap-south-1
aws ec2 describe-volumes --region ap-south-1 --filters Name=status,Values=available
eksctl delete cluster --name interview-eks --region ap-south-1 --wait
```
