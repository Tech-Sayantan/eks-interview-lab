# Teardown And Cost Control Checklist

This note records how to safely tear down the lab and what to check afterward.

## Why Teardown Matters

EKS labs can keep charging even when you are not using them.

Common chargeable resources:

- EKS control plane
- EC2 worker nodes
- EBS volumes
- ALB
- NAT Gateway, if created
- ECR image storage
- Secrets Manager secret
- Route 53 hosted zone
- CloudWatch logs

IAM roles and policies usually do not cost money, but stale IAM is still bad hygiene.

## Lab Teardown Command

We used:

```bash
CONFIRM_DESTROY=yes \
AWS_PROFILE=eks-lab \
AWS_REGION=us-east-1 \
CLUSTER_NAME=interview-eks \
NAMESPACE=interview \
HELM_RELEASE=interview-app \
ECR_REPOSITORY=interview-app \
IRSA_BUCKET_NAME=923988301700-us-east-1-interview-eks-irsa-demo \
DESTROY_ECR=true \
DESTROY_S3=true \
DESTROY_ACM=false \
bash infra/scripts/09-destroy.sh
```

What the script does:

- captures the ALB DNS name from Ingress
- uninstalls the Helm release
- deletes PVCs
- deletes the namespace
- waits for AWS Load Balancer Controller to delete the ALB
- deletes the EKS cluster through `eksctl`
- optionally deletes ECR repository
- optionally deletes IRSA S3 bucket
- optionally deletes ACM certificate

We kept `DESTROY_ACM=false` because the certificate is free and may be reused. Delete it later only if you are sure you no longer need it.

## Teardown Issue We Hit

During `eksctl delete cluster`, drain got stuck:

```text
1 pods are unevictable
```

Root cause:

Kube-system PDBs had `ALLOWED DISRUPTIONS=0`.

We checked:

```bash
kubectl get pdb -A
kubectl get pods -A -o wide
kubectl get nodes
```

Then removed teardown-blocking PDBs:

```bash
kubectl delete pdb coredns ebs-csi-controller metrics-server \
  -n kube-system --ignore-not-found=true
```

Why this is okay during teardown:

The environment is being destroyed. We are no longer preserving workload availability.

Interview lesson:

"PDBs can block voluntary disruptions such as node drain. During cluster deletion, you may need to remove PDBs or force deletion, but in production maintenance you should respect them."

## Post-Teardown AWS Checks

Run these after the script finishes:

```bash
aws eks list-clusters --region us-east-1 --profile eks-lab
aws elbv2 describe-load-balancers --region us-east-1 --profile eks-lab
aws ec2 describe-volumes --region us-east-1 --profile eks-lab
aws cloudformation list-stacks --region us-east-1 --profile eks-lab
aws ecr describe-repositories --region us-east-1 --profile eks-lab
aws secretsmanager list-secrets --region us-east-1 --profile eks-lab
```

Check manually in console too:

- EKS clusters
- EC2 instances
- Load Balancers
- Target Groups
- EBS Volumes
- NAT Gateways
- CloudFormation stacks with `eksctl-interview-eks`
- ECR
- Secrets Manager
- Route 53 records

## Route 53 Cleanup

The hosted zone may remain because the domain `tanscape.online` still exists.

Optional cleanup:

- delete only `app.tanscape.online` A/AAAA alias records
- keep hosted zone if you still want Route 53 DNS for the domain
- delete hosted zone only if you no longer want Route 53 for that domain

Important:

Deleting the hosted zone while GoDaddy still delegates to Route 53 will break DNS for the domain.

## Secrets Manager Cleanup

Secrets Manager charges monthly per secret.

If the lab secret is no longer needed:

```bash
aws secretsmanager delete-secret \
  --region us-east-1 \
  --profile eks-lab \
  --secret-id interview/app/demo \
  --force-delete-without-recovery
```

Use force delete only for disposable lab secrets. Production secrets usually use a recovery window.

## IAM Cleanup

IAM is free, but old permissions are risky.

Lab IAM names to check:

- `interview-eks-github-actions-deployer`
- `interview-eks-github-actions-deploy-policy`
- `interview-eks-interview-app-irsa`
- `interview-eks-interview-app-s3-policy`
- `interview-eks-AWSLoadBalancerControllerIAMPolicy`
- `interview-eks-AmazonEKSLoadBalancerControllerRole`
- `interview-eks-AmazonEKS_EBS_CSI_DriverRole`

Be careful:

Some roles may be deleted automatically with `eksctl`. Some custom policies may remain.

## Final Teardown Mental Model

Destroy in dependency order:

```text
Application workloads
-> Ingress and load balancer
-> PVC and storage
-> namespace
-> node group
-> control plane
-> ECR/S3/secrets/IAM cleanup
-> DNS cleanup
```

Why this order:

Kubernetes controllers need time to delete cloud resources they created. If the cluster is deleted too early, cloud resources can become orphaned.

