# Study Index

Use this as the table of contents for the final two-day revision.

## Read First

1. `06-today-lab-retrospective.md`
2. `09-kubernetes-production-troubleshooting-playbook.md`
3. `10-two-day-interview-study-plan.md`
4. `12-teardown-and-cost-control-checklist.md`

These three give the fastest return.

## Deep Dives

Read these when you want depth:

- `01-k8s-manifest-deep-dive.md`
- `02-helm-ci-aws-deep-dive.md`
- `03-kubectl-command-playbook.md`
- `04-aws-eks-networking-storage-deep-dive.md`
- `05-canary-alb-ingress-deep-dive.md`
- `07-eks-cluster-creation-networking-dns-deep-dive.md`
- `08-company-style-github-actions-cicd.md`

## What We Covered In Hands-On Practice

- IAM user/profile setup
- GitHub SSH and repo setup
- EKS cluster creation with `eksctl`
- Route 53 hosted zone and ACM certificate
- AWS Load Balancer Controller
- EBS CSI driver
- metrics-server
- VPC CNI NetworkPolicy support
- Docker build and ECR push
- Helm deployment
- GitHub Actions OIDC deployment
- IRSA and AWS Secrets Manager
- Deployment, Service, Ingress
- ConfigMap and Secret
- Redis StatefulSet, PVC, PV, StorageClass
- HPA
- NetworkPolicy
- DaemonSet
- ResourceQuota and LimitRange
- PDB and node drain
- Helm rollback
- ALB weighted canary
- CrashLoopBackOff
- ImagePullBackOff
- Redis dependency outage
- EBS zonal scheduling issue
- dashboard redeployment after rollback
- teardown
- teardown PDB blocker and cost cleanup

## Topics To Still Research Briefly

These are useful if you have extra time:

- Karpenter vs Cluster Autoscaler
- External Secrets Operator
- Argo CD and GitOps drift detection
- Argo Rollouts or Flagger for canary
- Pod Security Standards
- Kyverno or OPA Gatekeeper
- EKS managed node groups vs self-managed node groups
- private subnet EKS architecture with NAT Gateway and VPC endpoints
- Prometheus/Grafana/Loki/CloudWatch observability
- OpenTelemetry basics
- EKS cost controls and teardown checks

## Final Interview Mantra

When answering, structure your thoughts:

```text
What is the symptom?
Which layer owns that symptom?
What command proves it?
What is the likely root cause?
What is the safe fix?
How do we prevent it next time?
```

That structure will make you sound calm and senior even when the question is hard.
