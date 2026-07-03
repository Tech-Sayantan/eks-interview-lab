# Today Fast Track: One-Day EKS Practice Run

Use this when time is tight. The goal is one successful end-to-end run today, then deeper study tomorrow.

Assumption:

- GoDaddy domain already exists.
- Route 53 hosted zone already exists.
- You are okay deleting everything after practice.
- You want the simplest path that still teaches Docker, EKS, Helm, ALB Ingress, PVC/StatefulSet, IRSA, HPA, NetworkPolicy, probes, and GitHub Actions OIDC.

## What Not To Do Today

Skip these unless something forces you:

- Terraform.
- Argo CD.
- Private-only networking.
- NAT Gateway optimization.
- External Secrets.
- Cluster Autoscaler.
- Full production-grade IAM least privilege.

Today is for concepts and hands-on confidence.

## Safety Rule

Do not create AWS root access keys.

Use root only for:

- enabling MFA,
- billing/budget setup,
- creating an admin IAM user or IAM Identity Center user.

Then use that admin user/profile for the lab. Delete it after practice if this is a throwaway account.

## Details I Need From You

Send these safe values:

```text
AWS region:
AWS account ID:
Domain name:
App hostname:
Route 53 hosted zone already exists? yes/no
GitHub username:
GitHub repo name you want:
Cluster name:
Do you have AWS CLI configured locally? yes/no
Do you have Docker Desktop running? yes/no
```

Do not send:

- AWS secret access key.
- AWS password.
- GitHub token.
- root credentials.
- downloaded credential CSV.

## Today Timeline

### Block 1: 45-60 min, local and account setup

1. Enable root MFA.
2. Create budget alert.
3. Create admin IAM user or configure IAM Identity Center.
4. Configure AWS CLI profile.
5. Install/check tools:

```bash
aws --version
eksctl version
kubectl version --client=true
helm version --short
docker version
git --version
```

Checkpoint:

```bash
aws sts get-caller-identity --profile eks-lab
```

### Block 2: 30-45 min, GitHub and project push

1. Create GitHub repo.
2. Set up SSH key if needed.
3. Open project in VS Code:

```bash
cd /Users/sayantanchowdhury/Documents/Codex/2026-07-02/so-amr-ekta-interview-ache-2/outputs/eks-interview-lab
code .
```

4. Push code:

```bash
git init
git add .
git commit -m "Add EKS interview lab"
git branch -M main
git remote add origin git@github.com:<github-user>/<repo>.git
git push -u origin main
```

### Block 3: 30-60 min, ACM certificate

In AWS Console:

1. Go to ACM in your chosen region.
2. Request public certificate for `app.yourdomain.com`.
3. Use DNS validation.
4. Create validation record in Route 53.
5. Wait for `Issued`.
6. Copy certificate ARN.

### Block 4: 60-90 min, create EKS

Create `infra/eksctl/cluster.yaml` from the template and replace placeholders.

Then:

```bash
eksctl create cluster -f infra/eksctl/cluster.yaml --profile eks-lab
aws eks update-kubeconfig --region <region> --name <cluster-name> --profile eks-lab
kubectl get nodes -o wide
```

### Block 5: 45-60 min, add-ons

Install:

- VPC CNI NetworkPolicy support.
- metrics-server.
- EBS CSI.
- AWS Load Balancer Controller.

Use the manual guide Part 12 to Part 15.

### Block 6: 45-60 min, Docker image and Helm deploy

1. Create ECR repo.
2. Build image.
3. Push image.
4. Create app IRSA.
5. Create `manual-values/my-values.yaml`.
6. Helm deploy.

Checkpoint:

```bash
kubectl get deploy,sts,ds,svc,pvc,hpa,ingress,networkpolicy -n interview
```

### Block 7: 20-30 min, domain points to ALB

1. Get ALB DNS from Ingress.
2. In Route 53, update/create `A` alias for app hostname.
3. Test:

```bash
curl -i https://app.yourdomain.com/healthz
curl -s https://app.yourdomain.com/redis/incr
curl -s https://app.yourdomain.com/aws/identity
```

### Block 8: 90-120 min, concept practice

Run and understand:

```bash
kubectl get all -n interview
kubectl describe deploy interview-app -n interview
kubectl get networkpolicy -n interview
kubectl get pvc,pv -A
kubectl get hpa -n interview
kubectl get ingress -n interview
kubectl get events -n interview --sort-by=.lastTimestamp | tail -30
```

Practice explaining:

- liveness vs readiness vs startup probe,
- Service vs Ingress,
- Deployment vs StatefulSet,
- PV vs PVC vs StorageClass,
- IRSA,
- HPA,
- NetworkPolicy and CNI enforcement,
- ALB 503 debugging.

### Block 9: 30-60 min, destroy

```bash
helm uninstall interview-app -n interview --wait
kubectl delete pvc --all -n interview
kubectl delete namespace interview
eksctl delete cluster --name <cluster-name> --region <region> --profile eks-lab --wait
```

Then check AWS Console:

- EKS cluster gone.
- EC2 Load Balancers gone.
- EC2 Volumes gone or only expected ones remain.
- CloudFormation `eksctl-*` stacks gone.
- ECR repo deleted if you do not need it.
- S3 demo bucket deleted if created.

## If You Get Stuck

Send me:

```text
I am at Today Fast Track Block X.
Command I ran:
Output/error:
```

I will help you from that exact point.
