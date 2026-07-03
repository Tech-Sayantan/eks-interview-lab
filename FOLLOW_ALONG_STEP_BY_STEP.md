# EKS Interview Lab: Step-by-Step Follow-Along

Use this file as your main guide. Do not rush. The target is not just to finish the setup; the target is that you can explain each step in an interview.

Every phase has:

- Goal: what we are trying to achieve.
- Why it matters: what interviewers expect you to understand.
- Commands: what to run.
- Checkpoint: how to know it worked.
- Interview talk track: how to explain it simply.

## Before You Start

You need:

- AWS CLI configured on your laptop.
- Docker running.
- `kubectl`, `helm`, and `eksctl` installed.
- A GitHub repo ready.
- A domain bought in GoDaddy.
- Around 4 to 6 focused hours for the first full run.

Cost warning:

- This creates real AWS resources.
- Destroy everything when done.
- Do not leave the cluster running overnight unless you intentionally want to pay for it.

## Phase 0: Open The Lab Folder

Goal:

Get into the generated lab project.

Command:

```bash
cd /Users/sayantanchowdhury/Documents/Codex/2026-07-02/so-amr-ekta-interview-ache-2/outputs/eks-interview-lab
```

Checkpoint:

```bash
ls
```

You should see:

```text
README.md
FOLLOW_ALONG_STEP_BY_STEP.md
app
charts
infra
notes
```

Interview talk track:

> This repo has application code, Dockerfile, Helm chart, EKS setup scripts, GitHub Actions pipeline, and study notes in one place for practice. In production I might split platform and app repos, but for interview prep one repo keeps the feedback loop short.

## Phase 1: Create Your Local Environment File

Goal:

Put your personal values in `.env` so scripts can reuse them.

Command:

```bash
cp infra/scripts/env.example .env
```

Open `.env` in your editor and update these:

```bash
export AWS_REGION="ap-south-1"
export CLUSTER_NAME="interview-eks"
export K8S_VERSION="1.34"

export DOMAIN_NAME="yourdomain.com"
export APP_HOSTNAME="app.yourdomain.com"

export GITHUB_OWNER="your-github-user"
export GITHUB_REPO="eks-interview-lab"
export GITHUB_BRANCH="main"
```

Then load it:

```bash
source .env
```

Checkpoint:

```bash
echo "$AWS_REGION"
echo "$CLUSTER_NAME"
echo "$APP_HOSTNAME"
```

Why it matters:

This avoids hardcoding values across many commands.

Interview talk track:

> I keep environment-specific values outside templates. The same chart or scripts can be reused for another region, cluster, domain, or repo by changing values.

## Phase 2: Check Local Tools And AWS Identity

Goal:

Make sure your laptop can talk to AWS and has the required tools.

Command:

```bash
source .env
infra/scripts/00-check-tools.sh
```

Checkpoint:

You should see:

- AWS account identity.
- AWS CLI version.
- eksctl version.
- kubectl client version.
- Helm version.
- Docker version.

If AWS identity fails:

```bash
aws configure
aws sts get-caller-identity
```

Why it matters:

Most EKS setup failures are not Kubernetes problems. They are local AWS auth, region, IAM permission, or tooling problems.

Interview talk track:

> Before touching Kubernetes, I verify AWS identity, region, and tool versions. It saves time because a lot of cluster setup issues are really IAM or local environment issues.

## Phase 3: Understand The App Before AWS

Goal:

See what app we are deploying.

Files to inspect:

```bash
ls app
sed -n '1,220p' app/src/main.py
sed -n '1,120p' app/Dockerfile
```

What the app contains:

- `/healthz`: liveness endpoint.
- `/readyz`: readiness endpoint, checks Redis.
- `/config`: shows ConfigMap values.
- `/secret-check`: checks Secret existence without exposing it.
- `/redis/incr`: proves StatefulSet/PVC-backed Redis works.
- `/aws/identity`: proves IRSA works.
- `/burn`: generates CPU load for HPA.

Why it matters:

The app is intentionally designed to exercise interview topics.

Interview talk track:

> The app is simple, but each endpoint maps to a platform concept: probes, ConfigMap, Secret, StatefulSet storage, IRSA, and autoscaling.

## Phase 4: Create Route 53 Hosted Zone And ACM Certificate

Goal:

Move DNS control for your GoDaddy domain into Route 53 and request an HTTPS certificate.

Command:

```bash
source .env
infra/scripts/01-bootstrap-dns-acm.sh
```

What this does:

- Creates or reuses a Route 53 hosted zone.
- Prints AWS name servers.
- Requests an ACM certificate for `APP_HOSTNAME`.
- Creates DNS validation record in Route 53.

Manual GoDaddy step:

Copy the printed Route 53 name servers and set them as your domain name servers in GoDaddy.

Checkpoint:

Run this after a few minutes:

```bash
source .env
infra/scripts/01-bootstrap-dns-acm.sh
```

When ACM becomes issued, the script prints:

```bash
export CERTIFICATE_ARN="arn:aws:acm:..."
```

Paste that line into `.env`, then:

```bash
source .env
echo "$CERTIFICATE_ARN"
```

If it is stuck:

- GoDaddy nameservers may not have propagated.
- Domain spelling may be wrong.
- ACM certificate must be in the same region as the ALB.

Why it matters:

Ingress gives you routing inside Kubernetes, but real HTTPS needs DNS plus a certificate.

Interview talk track:

> For public HTTPS on EKS, I use Route 53 for DNS, ACM for TLS certificate, and AWS Load Balancer Controller to attach that certificate to an ALB created from Kubernetes Ingress.

## Phase 5: Create The EKS Cluster

Goal:

Create EKS control plane and self-managed worker nodes.

Command:

```bash
source .env
infra/scripts/02-create-cluster.sh
```

This can take 15 to 25 minutes.

What this creates:

- EKS control plane.
- VPC and subnets through eksctl.
- Self-managed EC2 node group.
- Spot worker nodes.
- IAM OIDC provider for IRSA.
- Core EKS add-ons.

Checkpoint:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Expected:

- Nodes should be `Ready`.
- `kube-system` pods should be running.

Why it matters:

You explicitly asked for self-managed nodes, not managed node groups and not Terraform for this round.

Interview talk track:

> In this lab I used eksctl to create a cluster with self-managed Spot nodes. EKS manages the control plane, but self-managed nodes are my responsibility for scaling, patching, AMI updates, and troubleshooting.

Important caveat:

This lab uses public worker nodes to avoid NAT Gateway cost. In production, private worker nodes are usually preferred.

## Phase 6: Install EKS Add-ons

Goal:

Install the cluster components required for storage, ingress, metrics, and NetworkPolicy.

Command:

```bash
source .env
infra/scripts/03-install-addons.sh
```

This installs/enables:

- Amazon VPC CNI NetworkPolicy support.
- metrics-server.
- EBS CSI driver with IRSA.
- AWS Load Balancer Controller with IRSA.

Checkpoint:

```bash
kubectl get pods -n kube-system
kubectl get deployment -n kube-system metrics-server
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get daemonset -n kube-system aws-node
```

Expected:

- `aws-node` pods running.
- `metrics-server` running.
- `aws-load-balancer-controller` running.
- EBS CSI controller running or EKS add-on active.

Why it matters:

Kubernetes objects often require controllers. A PVC needs a CSI driver. An Ingress needs an ingress controller. HPA needs metrics.

Interview talk track:

> Kubernetes is declarative. Creating an object is only half the story; a controller must watch that object and reconcile real infrastructure. For example, AWS Load Balancer Controller watches Ingress and creates an ALB.

## Phase 7: Build And Push Docker Image To ECR

Goal:

Containerize the app and push it to AWS ECR so EKS nodes can pull it.

Command:

```bash
source .env
infra/scripts/04-build-and-push.sh
```

Checkpoint:

The script prints:

```bash
export IMAGE_REPOSITORY="..."
export IMAGE_TAG="..."
```

Paste both into `.env`, then:

```bash
source .env
echo "$IMAGE_REPOSITORY"
echo "$IMAGE_TAG"
```

Check ECR:

```bash
aws ecr describe-images \
  --region "$AWS_REGION" \
  --repository-name "$ECR_REPOSITORY"
```

Why it matters:

Kubernetes does not build images. It schedules containers from already-built images.

Interview talk track:

> The CI/CD flow is: build image, push immutable tag to registry, then deploy that tag with Helm. Kubernetes pulls the image from ECR during pod creation.

## Phase 8: Create App IRSA Role

Goal:

Give only the app pod limited AWS permissions without storing AWS keys in the container.

Command:

```bash
source .env
infra/scripts/05-create-app-irsa.sh
```

Checkpoint:

The script prints:

```bash
export IRSA_BUCKET_NAME="..."
export APP_ROLE_ARN="..."
```

Paste both into `.env`, then:

```bash
source .env
echo "$APP_ROLE_ARN"
```

Why it matters:

IRSA is one of the most important EKS interview topics.

Interview talk track:

> IRSA maps a Kubernetes ServiceAccount to an IAM role through OIDC. The pod gets short-lived credentials through STS AssumeRoleWithWebIdentity. This avoids long-lived AWS keys and avoids giving every pod the node IAM role.

## Phase 9: Inspect The Helm Chart Before Deploying

Goal:

Understand what Kubernetes resources Helm will create.

Commands:

```bash
helm lint charts/interview-app \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$IMAGE_TAG" \
  --set "ingress.hosts[0].host=$APP_HOSTNAME"
```

Render locally:

```bash
helm template interview-app charts/interview-app \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$IMAGE_TAG" \
  --set "ingress.hosts[0].host=$APP_HOSTNAME" \
  > /tmp/interview-app-rendered.yaml
```

Look at objects:

```bash
grep '^kind:' /tmp/interview-app-rendered.yaml
```

Expected kinds include:

- ServiceAccount
- ConfigMap
- Secret
- Service
- NetworkPolicy
- ResourceQuota
- LimitRange
- StorageClass
- DaemonSet
- Deployment
- HPA
- PDB
- StatefulSet
- Ingress

Why it matters:

Helm is not magic. It renders Kubernetes YAML from templates and values.

Interview talk track:

> Before applying a Helm chart, I like to run `helm lint` and `helm template`. It lets me catch rendering errors before touching the cluster.

## Phase 10: Deploy The App With Helm

Goal:

Install the application and all Kubernetes resources.

Command:

```bash
source .env
infra/scripts/06-deploy.sh
```

Checkpoint:

```bash
kubectl get all -n interview
kubectl get pvc -n interview
kubectl get ingress -n interview
kubectl get networkpolicy -n interview
kubectl get hpa -n interview
```

Expected:

- Deployment pods running.
- Redis StatefulSet running.
- PVC bound.
- Ingress created.
- HPA created.
- NetworkPolicies created.

Why it matters:

This is the main Kubernetes practice phase.

Interview talk track:

> I deployed using Helm with environment-specific values. Helm created the Deployment, Service, Ingress, StatefulSet, PVC, StorageClass, NetworkPolicy, HPA, ConfigMap, Secret, ServiceAccount, ResourceQuota, LimitRange, PDB, and DaemonSet.

## Phase 11: Point Your Domain To The ALB

Goal:

Create Route 53 alias record so your app is reachable by your domain.

First check ALB:

```bash
kubectl get ingress -n interview
```

If the address is empty, wait and retry.

Then:

```bash
source .env
infra/scripts/07-route53-alias.sh
```

Checkpoint:

```bash
curl -i "https://${APP_HOSTNAME}/healthz"
curl -s "https://${APP_HOSTNAME}/"
curl -s "https://${APP_HOSTNAME}/redis/incr"
curl -s "https://${APP_HOSTNAME}/secret-check"
curl -s "https://${APP_HOSTNAME}/aws/identity"
```

Expected:

- `/healthz` returns healthy.
- `/redis/incr` increments counter.
- `/aws/identity` returns the IAM role identity if IRSA is working.

Why it matters:

This proves the full path: DNS -> ALB -> Ingress -> Service -> Pod -> Redis/AWS.

Interview talk track:

> The request path is domain DNS in Route 53, ALB created by AWS Load Balancer Controller, Kubernetes Ingress rule, ClusterIP Service, then selected app pods.

## Phase 12: Understand Probes

Goal:

Practice startup, liveness, and readiness probes.

Commands:

```bash
kubectl describe deploy interview-app -n interview | grep -A35 -E 'Liveness|Readiness|Startup'
kubectl get endpoints interview-app -n interview
kubectl describe pod -n interview -l app.kubernetes.io/component=web
```

What this lab uses:

- Startup probe: `/healthz`
- Liveness probe: `/healthz`
- Readiness probe: `/readyz`, which checks Redis

Try this thought experiment:

- If Redis breaks, readiness should fail.
- Failed readiness removes pod from Service endpoints.
- Liveness should not restart the pod just because Redis is down unless your app itself is dead.

Interview talk track:

> Liveness decides when kubelet restarts a container. Readiness decides whether the pod receives traffic. Startup protects slow-starting apps from being killed too early by liveness.

## Phase 13: Understand NetworkPolicy

Goal:

Practice pod-level traffic control.

Commands:

```bash
kubectl get networkpolicy -n interview
kubectl describe networkpolicy interview-app-web -n interview
kubectl describe networkpolicy interview-app-redis -n interview
```

What the policy does:

- Allows external/ALB traffic to app port `8080`.
- Allows app to Redis on `6379`.
- Allows app DNS to kube-system on `53`.
- Allows app HTTPS egress on `443` for AWS SDK/STS.
- Allows Redis ingress only from app pods.

Checkpoint:

```bash
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl describe daemonset aws-node -n kube-system | grep -E 'enable-network-policy|aws-network-policy-agent' -A3
```

Why it matters:

NetworkPolicy is a common first-round topic because people often know the YAML but forget CNI enforcement.

Interview talk track:

> NetworkPolicy is namespace-scoped and label-based. It is enforced only if the CNI supports it. On EKS, Amazon VPC CNI can enforce NetworkPolicy after enabling the feature.

## Phase 14: Practice HPA

Goal:

Trigger CPU load and watch pod autoscaling.

Command:

```bash
kubectl get hpa -n interview
```

Start load:

```bash
kubectl run load -n interview \
  --image=public.ecr.aws/docker/library/busybox:1.36 \
  --restart=Never \
  -- /bin/sh -c 'while true; do wget -q -O- http://interview-app.interview.svc.cluster.local/burn?seconds=3; done'
```

Watch:

```bash
kubectl get hpa -n interview -w
```

Stop with `Ctrl+C`, then clean up:

```bash
kubectl delete pod load -n interview --ignore-not-found=true
```

Why it matters:

HPA needs metrics-server and CPU requests.

Interview talk track:

> HPA scales pod replicas based on metrics. It does not add nodes. If new pods become Pending due to lack of capacity, Cluster Autoscaler or another node provisioning mechanism would be needed.

## Phase 15: Practice StatefulSet And PVC

Goal:

Understand persistent storage in Kubernetes on AWS.

Commands:

```bash
kubectl get sts -n interview
kubectl get pvc -n interview
kubectl get pv
kubectl get storageclass
kubectl describe pvc -n interview
```

Test persistence:

```bash
curl -s "https://${APP_HOSTNAME}/redis/incr"
kubectl delete pod -n interview interview-app-redis-0
kubectl rollout status statefulset/interview-app-redis -n interview
curl -s "https://${APP_HOSTNAME}/redis/incr"
```

Expected:

Counter should continue increasing after Redis pod restart because the PVC remains.

Interview talk track:

> StatefulSet gives stable identity and stable storage. The Redis pod gets a persistent volume through a volumeClaimTemplate and EBS CSI dynamically provisions an EBS volume.

## Phase 16: Practice GitHub Actions OIDC

Goal:

Deploy from GitHub Actions without storing AWS access keys.

Create AWS role:

```bash
source .env
infra/scripts/10-create-github-oidc-role.sh
```

Add the printed variables in GitHub repo settings:

```text
AWS_ROLE_ARN
AWS_REGION
CLUSTER_NAME
NAMESPACE
HELM_RELEASE
ECR_REPOSITORY
APP_HOSTNAME
CERTIFICATE_ARN
APP_ROLE_ARN
```

Push repo:

```bash
git init
git add .
git commit -m "Add EKS interview lab"
git branch -M main
git remote add origin git@github.com:<your-user>/eks-interview-lab.git
git push -u origin main
```

Checkpoint:

Go to GitHub Actions and watch the workflow.

Why it matters:

GitHub Actions OIDC is a strong modern CI/CD security topic.

Interview talk track:

> GitHub gets a short-lived OIDC token, AWS validates the token audience and subject in the IAM role trust policy, then the workflow assumes the role. No long-lived AWS keys are stored in GitHub.

## Phase 17: Break-Fix Practice

Goal:

Build debugging muscle for interview questions.

### Break Image Tag

```bash
helm upgrade interview-app charts/interview-app -n interview \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="bad-tag" \
  --set "ingress.hosts[0].host=$APP_HOSTNAME"
```

Debug:

```bash
kubectl get pods -n interview
kubectl describe pod -n interview <pod-name>
```

Fix:

```bash
source .env
infra/scripts/06-deploy.sh
```

### Break Readiness Mentally

Scale Redis to zero:

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=0
kubectl get endpoints interview-app -n interview
```

Then restore:

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=1
kubectl rollout status statefulset/interview-app-redis -n interview
```

### Inspect Events

```bash
kubectl get events -n interview --sort-by=.lastTimestamp | tail -30
```

Interview talk track:

> My first debugging steps are get, describe, logs, events, and checking selectors/endpoints. I try to determine whether the problem is scheduling, image pull, app crash, readiness, networking, storage, or IAM.

## Phase 18: Final Interview Revision

Read these:

```bash
less notes/interview-cheatsheet.md
less notes/troubleshooting-runbook.md
less notes/cost-guard.md
```

Practice saying these out loud:

- Docker image vs container.
- Deployment vs StatefulSet.
- Service vs Ingress.
- ConfigMap vs Secret.
- PV vs PVC vs StorageClass.
- HPA vs VPA vs Cluster Autoscaler.
- Liveness vs readiness vs startup probe.
- IRSA flow.
- GitHub Actions OIDC flow.
- NetworkPolicy and CNI enforcement.
- Why ALB might return 503.
- Why a pod might be Pending.
- Why PVC might be Pending.

## Phase 19: Destroy Everything

Goal:

Stop AWS charges.

Command:

```bash
source .env
infra/scripts/09-destroy.sh
```

Optional cleanup:

```bash
export DESTROY_ECR=true
export DESTROY_S3=true
export DESTROY_ACM=true
export CONFIRM_DESTROY=yes
infra/scripts/09-destroy.sh
```

Manual AWS Console check:

- EKS clusters.
- EC2 Load Balancers.
- EC2 Volumes.
- NAT Gateways.
- CloudFormation stacks.
- Route 53 hosted zone.

Interview talk track:

> For temporary environments, teardown is part of the workflow. I check for leftover load balancers, EBS volumes, CloudFormation stacks, and DNS records because those can keep charging after the main cluster is gone.

## How We Will Work Together

When you are ready, send me your safe values:

```text
AWS region:
Domain name:
App hostname:
GitHub owner:
GitHub repo name:
Preferred cluster name:
```

Then we will go phase by phase.

You run the command. You paste the output or error. I explain what happened, what it means, and the next step.

Do not send:

- AWS secret access keys.
- GitHub tokens.
- Passwords.
- Root credentials.
