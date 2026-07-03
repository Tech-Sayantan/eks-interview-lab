# Cost Guard

Use this lab like a timed exercise, not a pet environment.

## Cheapest Reasonable Choices

- Use one EKS cluster only.
- Use Kubernetes `1.34` or another standard-support version, not extended support.
- Use self-managed Spot nodes.
- Keep desired node count at 2, max 3.
- Avoid NAT Gateway for this lab.
- Keep Redis PVC at 2Gi.
- Destroy the ALB before deleting the cluster.
- Delete unused EBS volumes after teardown.

## What Costs Money

- EKS control plane per cluster hour.
- EC2 instances.
- Public IPv4 addresses.
- EBS volumes.
- ALB hours and LCU usage.
- Route 53 hosted zone.
- ECR image storage.
- S3 bucket storage and requests.

## Fast Teardown Checklist

```bash
source .env
helm uninstall interview-app -n interview --wait
kubectl delete pvc --all -n interview
infra/scripts/09-destroy.sh
```

Then inspect AWS Console:

- EC2 -> Load Balancers
- EC2 -> Volumes
- EC2 -> NAT Gateways
- EKS -> Clusters
- CloudFormation -> eksctl stacks
- Route 53 -> hosted zone

If VPC deletion fails, the usual reason is a leftover ALB, ENI, EBS volume, security group dependency, or NAT Gateway.
