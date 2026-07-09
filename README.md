# EKS Interview Lab

This is a compact 1 to 1.5 day hands-on lab for Kubernetes, Docker, Helm, GitHub Actions OIDC, and AWS EKS.

Documentation site: https://tech-sayantan.github.io/eks-interview-lab/

If you are doing the lab today, start with `START_HERE_TODAY.md`. It is the shortest clear entry point and tells you exactly what to do first.

If you want a very hand-held full walkthrough, use `MANUAL_FROM_ZERO_GUIDE.md`. It covers GitHub, AWS account access, local tool installation, VS Code, code push, EKS setup, Helm deploy, DNS, OIDC, practice, and teardown.

`FOLLOW_ALONG_STEP_BY_STEP.md` is a shorter command-first version after you are comfortable with the manual flow.

The goal is not to build a perfect production platform. The goal is to create one real EKS environment, deploy one real containerized app through Helm, expose it on your own domain, practice the most asked Kubernetes objects, and then destroy everything quickly.

## Architecture

GoDaddy domain -> Route 53 public hosted zone -> ACM certificate -> ALB Ingress -> Kubernetes Service -> app Pods.

Inside the cluster:

- `Deployment`: FastAPI sample app.
- `Service`: stable ClusterIP for the app.
- `Ingress`: AWS Load Balancer Controller creates an internet-facing ALB.
- `ConfigMap`: non-secret app config.
- `Secret`: demo secret mounted as env var.
- `ServiceAccount + IRSA`: app assumes an AWS IAM role without static keys.
- `StorageClass`: dynamic EBS provisioning through EBS CSI.
- `StatefulSet`: Redis with a PVC.
- `Headless Service`: stable DNS identity for Redis.
- `DaemonSet`: one small pod per node for DaemonSet practice.
- `ResourceQuota + LimitRange`: namespace guardrails.
- `HPA`: scales the app by CPU.
- `VPA`: optional object, disabled until VPA CRDs are installed.
- `NetworkPolicy`: restricts app and Redis traffic after VPC CNI policy support is enabled.

## Cost Posture

This lab intentionally uses self-managed Spot nodes and disables NAT Gateway in the eksctl template. That means the worker nodes are in public subnets for this practice setup. In production you normally place nodes in private subnets and use NAT Gateway or VPC endpoints, but NAT Gateway can cost more than the rest of a short practice lab.

Main chargeable items:

- EKS control plane.
- EC2 Spot instances and their public IPv4 addresses.
- ALB.
- EBS volumes for worker nodes and the Redis PVC.
- Route 53 hosted zone.
- Tiny ECR/S3 usage if you keep them.

Destroy the lab the same day or the next day. Do not leave the cluster running after practice.

## Repo Strategy

For interview practice, use this as one repository:

```text
app/                    # Dockerized FastAPI app
charts/interview-app/   # Helm chart
infra/                  # eksctl, IAM, DNS, ACM, deploy scripts
.github/workflows/      # GitHub Actions OIDC pipeline
notes/                  # study notes and troubleshooting
```

In a real company, you often split this into:

- `platform-eks`: cluster, add-ons, IAM, DNS, base policies.
- `app-service`: application, Dockerfile, Helm chart, pipeline.

For two-day prep, the mono-repo keeps context switching low.

## Prerequisites

Install and configure:

- AWS CLI v2
- `eksctl`
- `kubectl`
- `helm`
- Docker
- A GitHub repository
- AWS permissions for EKS, IAM, EC2, ELB, ECR, S3, Route 53, ACM, and CloudFormation

Set a billing alarm in AWS before starting.

## Execution Order

Run from this folder:

```bash
cd /Users/sayantanchowdhury/Documents/Codex/2026-07-02/so-amr-ekta-interview-ache-2/outputs/eks-interview-lab
cp infra/scripts/env.example .env
```

Edit `.env`:

```bash
export AWS_REGION="ap-south-1"
export CLUSTER_NAME="interview-eks"
export DOMAIN_NAME="yourdomain.com"
export APP_HOSTNAME="app.yourdomain.com"
export GITHUB_OWNER="your-github-user"
export GITHUB_REPO="eks-interview-lab"
```

Then:

```bash
source .env
infra/scripts/00-check-tools.sh
```

### 1. Route 53 and ACM

```bash
source .env
infra/scripts/01-bootstrap-dns-acm.sh
```

Copy the printed Route 53 name servers into GoDaddy for your domain. Run the script again after nameserver delegation if ACM validation is still pending.

When the script prints `CERTIFICATE_ARN`, paste it into `.env` and run:

```bash
source .env
```

### 2. Create EKS with Self-Managed Nodes

```bash
source .env
infra/scripts/02-create-cluster.sh
```

The eksctl template uses:

- Kubernetes `1.34` by default.
- Self-managed node group through `nodeGroups`.
- Spot capacity through `instancesDistribution`.
- Amazon Linux 2023 nodes.
- Public cluster endpoint.
- No NAT Gateway for cost control.
- OIDC enabled for IRSA.

### 3. Install Cluster Add-ons

```bash
source .env
infra/scripts/03-install-addons.sh
```

This installs:

- Amazon VPC CNI NetworkPolicy support.
- `metrics-server` for HPA CPU metrics.
- EBS CSI driver as an EKS add-on with IRSA.
- AWS Load Balancer Controller with IRSA and Helm.

### 4. Build and Push the App Image

```bash
source .env
infra/scripts/04-build-and-push.sh
```

Paste the printed `IMAGE_REPOSITORY` and `IMAGE_TAG` into `.env`, then:

```bash
source .env
```

### 5. Create App IRSA Role

```bash
source .env
infra/scripts/05-create-app-irsa.sh
```

Paste the printed `APP_ROLE_ARN` and `IRSA_BUCKET_NAME` into `.env`, then:

```bash
source .env
```

### 6. Deploy with Helm

```bash
source .env
infra/scripts/06-deploy.sh
```

Check the ALB DNS:

```bash
kubectl get ingress -n interview
```

Check probes and NetworkPolicies:

```bash
kubectl describe deploy interview-app -n interview | grep -A30 -E 'Liveness|Readiness|Startup'
kubectl get networkpolicy -n interview
kubectl describe networkpolicy interview-app-web -n interview
```

### 7. Point Your Domain to the ALB

```bash
source .env
infra/scripts/07-route53-alias.sh
```

Then test:

```bash
curl -i "https://${APP_HOSTNAME}/"
curl -s "https://${APP_HOSTNAME}/redis/incr"
curl -s "https://${APP_HOSTNAME}/aws/identity"
```

### 8. Practice Live Debugging

```bash
source .env
infra/scripts/08-practice-commands.sh
```

Trigger HPA:

```bash
kubectl run load -n interview --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://interview-app.interview.svc.cluster.local/burn?seconds=3; done'
kubectl get hpa -n interview -w
```

Clean the load pod:

```bash
kubectl delete pod load -n interview --ignore-not-found=true
```

### 9. GitHub Actions OIDC

Create the GitHub OIDC role:

```bash
source .env
infra/scripts/10-create-github-oidc-role.sh
```

In GitHub repository settings, add repository variables:

```text
AWS_ROLE_ARN=<printed role arn>
AWS_REGION=ap-south-1
CLUSTER_NAME=interview-eks
NAMESPACE=interview
HELM_RELEASE=interview-app
ECR_REPOSITORY=interview-app
APP_HOSTNAME=app.yourdomain.com
CERTIFICATE_ARN=<your ACM cert arn>
APP_ROLE_ARN=<your app IRSA role arn>
```

Push the repo:

```bash
git init
git add .
git commit -m "Add EKS interview lab"
git branch -M main
git remote add origin git@github.com:<your-user>/eks-interview-lab.git
git push -u origin main
```

The workflow builds the Docker image, pushes it to ECR, updates kubeconfig through OIDC, and deploys with Helm.

## Destroy

When done:

```bash
source .env
infra/scripts/09-destroy.sh
```

To also remove optional leftovers:

```bash
export DESTROY_ECR=true
export DESTROY_S3=true
export DESTROY_ACM=true
export CONFIRM_DESTROY=yes
infra/scripts/09-destroy.sh
```

After destroy, manually check:

- EKS clusters
- EC2 Load Balancers
- EC2 Volumes
- NAT Gateways
- CloudFormation stacks named `eksctl-*`
- Route 53 hosted zone, if you no longer need it

## 1.5 Day Study Plan

Day 1 morning:

- Tools, AWS account sanity check, Route 53/ACM.
- Create EKS cluster.
- Learn EKS control plane vs worker nodes, self-managed vs managed nodes, public vs private subnets.

Day 1 afternoon:

- Install add-ons.
- Build/push Docker image.
- Deploy Helm chart.
- Understand Deployment, Service, Ingress, ConfigMap, Secret, ServiceAccount.

Day 1 evening:

- Practice PVC/PV/StorageClass/StatefulSet.
- Break and fix image tag, readiness probe, resource quota, NetworkPolicy, and ALB health check.
- Practice `kubectl describe`, events, logs, rollout, and exec.

Day 2 morning:

- Configure GitHub Actions OIDC.
- Push code, watch pipeline, explain the trust policy.
- Practice HPA and IRSA.

Day 2 before interview:

- Read `notes/interview-cheatsheet.md`.
- Speak answers aloud.
- Destroy everything.

## Official References Checked

- Amazon EKS Kubernetes version lifecycle: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- Amazon EKS pricing: https://aws.amazon.com/eks/pricing/
- eksctl Spot/self-managed node groups: https://docs.aws.amazon.com/eks/latest/eksctl/spot-instances.html
- AWS Load Balancer Controller: https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
- EBS CSI driver: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
- IRSA: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- GitHub Actions OIDC with AWS: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws
