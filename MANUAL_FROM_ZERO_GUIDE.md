# Manual From-Zero Guide: GitHub + AWS + Local Laptop + EKS

This is the guide you asked for: no repeated `source .env`, no assumption that you remember everything, and no big jump from one topic to another.

You will do the work yourself. I will guide you step by step.

Use this style:

- Browser step: where to click.
- Terminal step: what command to run.
- Checkpoint: how to know it worked.
- Interview point: what to say if asked.

## Your Values

Keep these values in a note somewhere. Replace placeholders in commands manually.

```text
AWS_REGION              = ap-south-1
AWS_PROFILE             = eks-lab
CLUSTER_NAME            = interview-eks
K8S_VERSION             = 1.34
DOMAIN_NAME             = yourdomain.com
APP_HOSTNAME            = app.yourdomain.com
GITHUB_OWNER            = your-github-username
GITHUB_REPO             = eks-interview-lab
NAMESPACE               = interview
HELM_RELEASE            = interview-app
ECR_REPOSITORY          = interview-app
```

Example:

If your domain is `mydemo.in`, then:

```text
DOMAIN_NAME  = mydemo.in
APP_HOSTNAME = app.mydemo.in
```

## Part 1: AWS Account Safety Setup

### 1.1 Log In To AWS

Browser:

1. Go to `https://console.aws.amazon.com/`.
2. Log in to your AWS account.
3. Do not use root user for daily work after initial setup.

### 1.2 Enable MFA

Browser:

1. Search for `IAM`.
2. Go to `IAM`.
3. If using root, open `Security credentials`.
4. Enable MFA for root.
5. Also enable MFA for your IAM/admin user if you create one.

Interview point:

> Root should be protected with MFA and not used for daily work. Human access should use IAM Identity Center or IAM users/roles with MFA.

### 1.3 Create A Budget Alarm

Browser:

1. Search for `Billing and Cost Management`.
2. Go to `Budgets`.
3. Create a monthly cost budget.
4. Set a small amount like `$10` or `$20`.
5. Add your email alert.

Why:

This lab creates real chargeable resources.

## Part 2: Create AWS CLI Access

Best practice is IAM Identity Center/SSO because AWS recommends temporary credentials instead of long-term access keys. For a quick personal lab, you can use an IAM user access key, but delete the key after the practice.

### Option A: Recommended, IAM Identity Center / SSO

Use this if your AWS account already has IAM Identity Center enabled.

Browser:

1. Search `IAM Identity Center`.
2. Enable it if needed.
3. Create a user for yourself.
4. Create a permission set with enough lab permissions.
5. Assign the user to your AWS account.

Terminal:

```bash
aws configure sso --profile eks-lab
aws sso login --profile eks-lab
aws sts get-caller-identity --profile eks-lab
```

Checkpoint:

You should see your AWS account ID.

### Option B: Faster Lab Method, IAM User Access Key

Use this only in your personal lab account. Delete the access key after the interview practice.

Browser:

1. AWS Console -> search `IAM`.
2. Left sidebar -> `Users`.
3. Click `Create user`.
4. User name: `eks-lab-cli`.
5. For console access, you can leave it off if you only need CLI access.
6. Permissions:
   - For this short lab, attach `AdministratorAccess`.
   - This is broad, but EKS creation touches EKS, IAM, EC2, CloudFormation, ELB, ECR, Route 53, ACM, S3, and STS.
   - Delete this user/key after practice.
7. Create user.
8. Open the user -> `Security credentials`.
9. Under `Access keys`, click `Create access key`.
10. Choose `Command Line Interface (CLI)`.
11. Confirm you understand the recommendation.
12. Create access key.
13. Download the CSV once.

Do not send this CSV to me.

Terminal:

```bash
aws configure --profile eks-lab
```

Enter:

```text
AWS Access Key ID: from CSV
AWS Secret Access Key: from CSV
Default region name: ap-south-1
Default output format: json
```

Checkpoint:

```bash
aws sts get-caller-identity --profile eks-lab
```

Expected:

You should see:

```json
{
  "UserId": "...",
  "Account": "...",
  "Arn": "arn:aws:iam::<account-id>:user/eks-lab-cli"
}
```

Interview point:

> Long-lived access keys are not ideal. For a real company I prefer IAM Identity Center or role-based temporary credentials. For this short personal lab, if I use an IAM user key, I delete it immediately after practice.

## Part 3: Install Local Tools On Mac

### 3.1 Install Homebrew

Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

If Homebrew is already installed:

```bash
brew --version
```

### 3.2 Install CLI Tools

Terminal:

```bash
brew install awscli eksctl kubectl helm git jq
brew install --cask docker visual-studio-code
```

Open Docker Desktop once:

```bash
open -a Docker
```

Wait until Docker says it is running.

Checkpoint:

```bash
aws --version
eksctl version
kubectl version --client=true
helm version --short
git --version
docker version
```

Interview point:

> For EKS work, I need AWS CLI for AWS APIs, eksctl for cluster creation, kubectl for Kubernetes API, Helm for packaging/deploying manifests, Docker for image build, and Git for source control.

## Part 4: Create GitHub Repository

Browser:

1. Go to `https://github.com/`.
2. Click `+` -> `New repository`.
3. Repository name: `eks-interview-lab`.
4. Choose private or public.
5. Do not initialize with README, `.gitignore`, or license.
6. Click `Create repository`.

Keep the SSH remote URL:

```text
git@github.com:<GITHUB_OWNER>/eks-interview-lab.git
```

## Part 5: Set Up GitHub SSH From Your Laptop

Check if you already have SSH key:

```bash
ls -la ~/.ssh
```

If you see `id_ed25519.pub`, you may already have one.

If not, create one:

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

Press Enter for the default file path. Add a passphrase if you want.

Start SSH agent and add key:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Copy public key:

```bash
pbcopy < ~/.ssh/id_ed25519.pub
```

Browser:

1. GitHub -> profile picture -> `Settings`.
2. `SSH and GPG keys`.
3. `New SSH key`.
4. Title: `MacBook`.
5. Paste key.
6. Save.

Test:

```bash
ssh -T git@github.com
```

Expected:

GitHub should greet your username.

## Part 6: Open The Project In VS Code

You already have the generated lab here:

```text
/Users/sayantanchowdhury/Documents/Codex/2026-07-02/so-amr-ekta-interview-ache-2/outputs/eks-interview-lab
```

Terminal:

```bash
cd /Users/sayantanchowdhury/Documents/Codex/2026-07-02/so-amr-ekta-interview-ache-2/outputs/eks-interview-lab
code .
```

If `code` command does not work:

1. Open VS Code manually.
2. Press `Cmd + Shift + P`.
3. Search `Shell Command: Install 'code' command in PATH`.
4. Run it.
5. Retry `code .`.

## Part 7: Understand The Directory Structure

In VS Code, inspect:

```text
app/
  Dockerfile
  requirements.txt
  src/main.py

charts/interview-app/
  Chart.yaml
  values.yaml
  templates/

infra/
  eksctl/
  iam/
  scripts/

.github/workflows/
  build-deploy.yml

notes/
  interview-cheatsheet.md
  troubleshooting-runbook.md
  cost-guard.md
```

What each folder means:

- `app`: application code and Dockerfile.
- `charts`: Helm chart for Kubernetes objects.
- `infra`: AWS/EKS helper configs and scripts.
- `.github/workflows`: CI/CD pipeline.
- `notes`: interview preparation.

Interview point:

> The app code, Helm deployment package, infrastructure helper files, and CI/CD workflow are separated by responsibility.

## Part 8: Push The Code To GitHub

Terminal:

```bash
cd /Users/sayantanchowdhury/Documents/Codex/2026-07-02/so-amr-ekta-interview-ache-2/outputs/eks-interview-lab
git init
git add .
git commit -m "Add EKS interview lab"
git branch -M main
git remote add origin git@github.com:<GITHUB_OWNER>/eks-interview-lab.git
git push -u origin main
```

Replace `<GITHUB_OWNER>` with your GitHub username/org.

Checkpoint:

Refresh GitHub repo page. You should see the project files.

## Part 9: Create Route 53 Hosted Zone Manually

Goal:

Move DNS hosting from GoDaddy to Route 53.

Browser:

1. AWS Console -> search `Route 53`.
2. Left sidebar -> `Hosted zones`.
3. Click `Create hosted zone`.
4. Domain name: your root domain, example `yourdomain.com`.
5. Type: `Public hosted zone`.
6. Create.
7. Open hosted zone.
8. Copy the 4 NS records.

GoDaddy:

1. Open your domain.
2. DNS management.
3. Nameservers.
4. Choose custom nameservers.
5. Paste the 4 Route 53 nameservers.
6. Save.

Checkpoint:

DNS propagation can take time.

```bash
dig NS yourdomain.com
```

Expected:

You should eventually see the Route 53 nameservers.

Interview point:

> GoDaddy is the registrar, but Route 53 is the authoritative DNS hosted zone after nameserver delegation.

## Part 10: Request ACM Certificate Manually

Goal:

Create an HTTPS certificate for `app.yourdomain.com`.

Browser:

1. AWS Console -> switch to region `ap-south-1`.
2. Search `Certificate Manager`.
3. Click `Request certificate`.
4. Choose `Request a public certificate`.
5. Domain name: `app.yourdomain.com`.
6. Validation method: `DNS validation`.
7. Request.
8. Open the certificate.
9. If AWS shows `Create records in Route 53`, click it.
10. Wait until status becomes `Issued`.

Copy the certificate ARN. You will need it later.

It looks like:

```text
arn:aws:acm:ap-south-1:<account-id>:certificate/<id>
```

Interview point:

> ACM certificate must be in the same region as the ALB. DNS validation proves domain ownership.

## Part 11: Create EKS Cluster From VS Code/Terminal

We will not use the `.env` style here. Instead, create a real cluster config file from the template.

Open:

```text
infra/eksctl/cluster-template.yaml
```

Create a copy:

```bash
cp infra/eksctl/cluster-template.yaml infra/eksctl/cluster.yaml
```

In VS Code, open `infra/eksctl/cluster.yaml` and replace:

```text
__CLUSTER_NAME__    -> interview-eks
__AWS_REGION__      -> ap-south-1
__K8S_VERSION__     -> 1.34
```

Also replace this in tags:

```text
k8s.io/cluster-autoscaler/__CLUSTER_NAME__
```

with:

```text
k8s.io/cluster-autoscaler/interview-eks
```

Create cluster:

```bash
eksctl create cluster -f infra/eksctl/cluster.yaml --profile eks-lab
```

Wait. This may take 15 to 25 minutes.

Update kubeconfig:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name interview-eks \
  --profile eks-lab
```

Checkpoint:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Expected:

Nodes should be `Ready`.

Interview point:

> eksctl created the EKS control plane and a self-managed node group. EKS manages the API server and etcd; I own worker node lifecycle because this is self-managed.

## Part 12: Enable NetworkPolicy In VPC CNI

Command:

```bash
aws eks update-addon \
  --region ap-south-1 \
  --cluster-name interview-eks \
  --addon-name vpc-cni \
  --resolve-conflicts OVERWRITE \
  --configuration-values '{"enableNetworkPolicy":"true","nodeAgent":{"healthProbeBindAddr":"8163","metricsBindAddr":"8162"}}' \
  --profile eks-lab
```

Wait:

```bash
aws eks wait addon-active \
  --region ap-south-1 \
  --cluster-name interview-eks \
  --addon-name vpc-cni \
  --profile eks-lab
```

Checkpoint:

```bash
kubectl rollout status daemonset/aws-node -n kube-system --timeout=180s
kubectl get pods -n kube-system -l k8s-app=aws-node
```

Interview point:

> A Kubernetes NetworkPolicy object needs CNI enforcement. On EKS, Amazon VPC CNI can enforce NetworkPolicy after enabling the feature.

## Part 13: Install Metrics Server

Command:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Checkpoint:

```bash
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s
kubectl top nodes
```

If `kubectl top nodes` does not work immediately, wait a minute.

Interview point:

> HPA needs metrics. For CPU/memory autoscaling, metrics-server provides resource metrics to Kubernetes.

## Part 14: Install EBS CSI Driver

Goal:

Enable dynamic EBS volume provisioning for PVCs.

Create IAM service account role:

```bash
eksctl create iamserviceaccount \
  --cluster interview-eks \
  --region ap-south-1 \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --role-name interview-eks-AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --override-existing-serviceaccounts \
  --profile eks-lab
```

Get your AWS account ID:

```bash
aws sts get-caller-identity --profile eks-lab --query Account --output text
```

Now create EKS add-on. Replace `<ACCOUNT_ID>`:

```bash
aws eks create-addon \
  --region ap-south-1 \
  --cluster-name interview-eks \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::<ACCOUNT_ID>:role/interview-eks-AmazonEKS_EBS_CSI_DriverRole \
  --resolve-conflicts OVERWRITE \
  --profile eks-lab
```

If it already exists, use update:

```bash
aws eks update-addon \
  --region ap-south-1 \
  --cluster-name interview-eks \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::<ACCOUNT_ID>:role/interview-eks-AmazonEKS_EBS_CSI_DriverRole \
  --resolve-conflicts OVERWRITE \
  --profile eks-lab
```

Checkpoint:

```bash
kubectl get pods -n kube-system | grep ebs
```

Interview point:

> PVCs are Kubernetes requests for storage, but AWS EBS volumes are provisioned by the EBS CSI driver. Without the CSI driver and IAM permission, PVCs can stay Pending.

## Part 15: Install AWS Load Balancer Controller

Goal:

Make Kubernetes Ingress create an AWS ALB.

Download IAM policy:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json \
  -o /tmp/aws-load-balancer-controller-iam-policy.json
```

Create policy:

```bash
aws iam create-policy \
  --policy-name interview-eks-AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/aws-load-balancer-controller-iam-policy.json \
  --profile eks-lab
```

If it says policy already exists, that is okay.

Get account ID:

```bash
aws sts get-caller-identity --profile eks-lab --query Account --output text
```

Create service account:

```bash
eksctl create iamserviceaccount \
  --cluster interview-eks \
  --region ap-south-1 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name interview-eks-AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/interview-eks-AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --override-existing-serviceaccounts \
  --profile eks-lab
```

Get VPC ID:

```bash
aws eks describe-cluster \
  --region ap-south-1 \
  --name interview-eks \
  --profile eks-lab \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text
```

Install controller:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

Replace `<VPC_ID>`:

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=interview-eks \
  --set region=ap-south-1 \
  --set vpcId=<VPC_ID> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Checkpoint:

```bash
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

Interview point:

> Ingress by itself does not create a load balancer. AWS Load Balancer Controller watches Ingress and creates ALB, listeners, target groups, and related AWS resources.

## Part 16: Create ECR Repository

Command:

```bash
aws ecr create-repository \
  --region ap-south-1 \
  --repository-name interview-app \
  --image-scanning-configuration scanOnPush=true \
  --profile eks-lab
```

If it already exists, continue.

Get account ID:

```bash
aws sts get-caller-identity --profile eks-lab --query Account --output text
```

Your ECR image repository will be:

```text
<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/interview-app
```

## Part 17: Build Docker Image

From project root:

```bash
docker build --platform linux/amd64 \
  -t <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/interview-app:manual-v1 \
  app
```

Login to ECR:

```bash
aws ecr get-login-password \
  --region ap-south-1 \
  --profile eks-lab \
  | docker login \
      --username AWS \
      --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
```

Push:

```bash
docker push <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/interview-app:manual-v1
```

Checkpoint:

```bash
aws ecr describe-images \
  --region ap-south-1 \
  --repository-name interview-app \
  --profile eks-lab
```

Interview point:

> Kubernetes pulls images from a registry. The CI/CD process builds an immutable image tag and Helm deploys that exact tag.

## Part 18: Create App IRSA Role Manually

Goal:

Let the app call AWS STS/S3 through a service account IAM role.

For the first run, you can use the prepared script because manual IAM OIDC trust JSON is easy to mistype.

Run:

```bash
AWS_PROFILE=eks-lab \
AWS_REGION=ap-south-1 \
CLUSTER_NAME=interview-eks \
NAMESPACE=interview \
infra/scripts/05-create-app-irsa.sh
```

The script prints:

```text
APP_ROLE_ARN
IRSA_BUCKET_NAME
```

Copy those values into your notes.

Interview point:

> IRSA maps Kubernetes ServiceAccount to IAM Role through OIDC. AWS SDK inside the pod gets short-lived credentials by calling STS AssumeRoleWithWebIdentity.

## Part 19: Create A Helm Values File Manually

Create:

```bash
mkdir -p manual-values
touch manual-values/my-values.yaml
```

Open `manual-values/my-values.yaml` in VS Code and paste this.

Replace:

- `<ACCOUNT_ID>`
- `<CERTIFICATE_ARN>`
- `<APP_ROLE_ARN>`
- `app.yourdomain.com`

```yaml
image:
  repository: "<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/interview-app"
  tag: "manual-v1"

config:
  appEnv: "eks"
  appMessage: "deployed manually with Helm on EKS"

ingress:
  certificateArn: "<CERTIFICATE_ARN>"
  hosts:
    - host: "app.yourdomain.com"
      paths:
        - path: /
          pathType: Prefix

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "<APP_ROLE_ARN>"
```

Why:

This replaces repeated `.env` sourcing. You have one visible values file for Helm.

Interview point:

> Helm values separate environment-specific data from reusable templates.

## Part 20: Deploy With Helm

Lint first:

```bash
helm lint charts/interview-app -f manual-values/my-values.yaml
```

Render and inspect:

```bash
helm template interview-app charts/interview-app \
  -f manual-values/my-values.yaml \
  > /tmp/interview-app-rendered.yaml
```

Check object kinds:

```bash
grep '^kind:' /tmp/interview-app-rendered.yaml
```

Create namespace:

```bash
kubectl create namespace interview --dry-run=client -o yaml | kubectl apply -f -
```

Deploy:

```bash
helm upgrade --install interview-app charts/interview-app \
  --namespace interview \
  -f manual-values/my-values.yaml \
  --wait \
  --timeout 10m
```

Checkpoint:

```bash
kubectl get deploy,sts,ds,svc,pvc,hpa,ingress,networkpolicy -n interview
```

Interview point:

> `helm upgrade --install` is idempotent. It installs the release if missing and upgrades it if it already exists.

## Part 21: Create Route 53 Alias To ALB

Get ALB DNS:

```bash
kubectl get ingress interview-app \
  -n interview \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
```

If empty, wait 1 to 3 minutes.

Browser manual method:

1. AWS Console -> Route 53.
2. Hosted zones -> your domain.
3. Create record.
4. Record name: `app`.
5. Record type: `A`.
6. Toggle `Alias`.
7. Route traffic to: `Alias to Application and Classic Load Balancer`.
8. Region: `ap-south-1`.
9. Choose the ALB created by Kubernetes.
10. Create record.

Test:

```bash
curl -i https://app.yourdomain.com/healthz
curl -s https://app.yourdomain.com/
curl -s https://app.yourdomain.com/redis/incr
curl -s https://app.yourdomain.com/aws/identity
```

Interview point:

> The final request path is Route 53 DNS -> ALB -> Kubernetes Ingress -> Service -> Pod.

## Part 22: Practice Kubernetes Concepts

### Probes

```bash
kubectl describe deploy interview-app -n interview | grep -A35 -E 'Liveness|Readiness|Startup'
```

Talk:

> Startup protects slow boot, liveness restarts stuck containers, readiness controls traffic routing.

### NetworkPolicy

```bash
kubectl get networkpolicy -n interview
kubectl describe networkpolicy interview-app-web -n interview
kubectl describe networkpolicy interview-app-redis -n interview
```

Talk:

> NetworkPolicy is label-based and namespace-scoped. It only works when the CNI enforces it.

### Storage

```bash
kubectl get storageclass
kubectl get pvc -n interview
kubectl get pv
```

Talk:

> PVC is the claim, PV is the actual volume, StorageClass defines dynamic provisioning through EBS CSI.

### StatefulSet

```bash
kubectl get sts -n interview
kubectl get pod interview-app-redis-0 -n interview -o wide
```

Talk:

> StatefulSet gives stable identity, ordered rollout, and stable PVC per replica.

### HPA

```bash
kubectl get hpa -n interview
kubectl top pods -n interview
```

Trigger load:

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

Cleanup:

```bash
kubectl delete pod load -n interview --ignore-not-found=true
```

Talk:

> HPA changes pod replica count. It does not add nodes. Node scaling needs Cluster Autoscaler or another provisioner.

## Part 23: Set Up GitHub Actions OIDC

This is a little IAM-heavy. Use the helper script for the first pass, then inspect generated IAM role in AWS console.

Run:

```bash
AWS_PROFILE=eks-lab \
AWS_REGION=ap-south-1 \
CLUSTER_NAME=interview-eks \
NAMESPACE=interview \
HELM_RELEASE=interview-app \
ECR_REPOSITORY=interview-app \
GITHUB_OWNER=<GITHUB_OWNER> \
GITHUB_REPO=eks-interview-lab \
GITHUB_BRANCH=main \
APP_HOSTNAME=app.yourdomain.com \
CERTIFICATE_ARN=<CERTIFICATE_ARN> \
APP_ROLE_ARN=<APP_ROLE_ARN> \
infra/scripts/10-create-github-oidc-role.sh
```

It prints GitHub repository variables.

Browser:

1. GitHub repo -> `Settings`.
2. `Secrets and variables`.
3. `Actions`.
4. `Variables`.
5. Add the printed variables:
   - `AWS_ROLE_ARN`
   - `AWS_REGION`
   - `CLUSTER_NAME`
   - `NAMESPACE`
   - `HELM_RELEASE`
   - `ECR_REPOSITORY`
   - `APP_HOSTNAME`
   - `CERTIFICATE_ARN`
   - `APP_ROLE_ARN`

Push a small change:

```bash
git status
git add .
git commit -m "Update manual lab guide"
git push
```

Browser:

1. GitHub repo -> `Actions`.
2. Open workflow run.
3. Watch build and deploy.

Interview point:

> GitHub Actions uses OIDC to get short-lived AWS credentials. The AWS role trust policy restricts which repo and branch can assume the role. No static AWS keys are stored in GitHub.

## Part 24: Debugging Practice

Run:

```bash
kubectl get pods -n interview -o wide
kubectl get events -n interview --sort-by=.lastTimestamp | tail -30
kubectl describe pod -n interview <pod-name>
kubectl logs -n interview <pod-name>
```

If ALB returns 503:

```bash
kubectl get endpoints -n interview
kubectl describe ingress interview-app -n interview
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

If PVC pending:

```bash
kubectl describe pvc -n interview
kubectl get pods -n kube-system | grep ebs
```

If HPA unknown:

```bash
kubectl top nodes
kubectl top pods -n interview
kubectl describe hpa interview-app -n interview
```

If IRSA fails:

```bash
kubectl get sa interview-app -n interview -o yaml
curl -s https://app.yourdomain.com/aws/identity
```

Interview point:

> I debug from outside to inside: DNS/ALB, Ingress, Service, Endpoints, Pod readiness, logs, events, IAM, storage, and metrics depending on the symptom.

## Part 25: Destroy Everything

First delete the Helm release:

```bash
helm uninstall interview-app -n interview --wait
kubectl delete pvc --all -n interview
kubectl delete namespace interview
```

Delete cluster:

```bash
eksctl delete cluster \
  --name interview-eks \
  --region ap-south-1 \
  --profile eks-lab \
  --wait
```

Manual AWS Console cleanup:

1. EC2 -> Load Balancers: none left.
2. EC2 -> Volumes: delete unattached lab volumes.
3. EKS -> Clusters: deleted.
4. CloudFormation -> no `eksctl-interview-eks-*` stacks.
5. ECR -> delete `interview-app` if no longer needed.
6. S3 -> delete IRSA demo bucket if created.
7. ACM -> delete certificate if no longer needed.
8. Route 53 -> delete hosted zone if you no longer want AWS DNS.
9. IAM -> delete lab access key/user if you used Option B.

Interview point:

> Teardown matters because cloud resources can continue charging after the main app is gone, especially ALB, EBS volumes, NAT gateways, ECR, and hosted zones.

## What You Should Send Me While Practicing

Send me:

```text
I am at Part X.
This is the command I ran.
This is the output/error.
```

Do not send:

- AWS secret access key.
- GitHub token.
- Password.
- Root credentials.
- Full downloaded credential CSV.

## Official References

- AWS IAM recommends temporary credentials over long-term access keys: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- AWS CLI SSO setup: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html
- IAM user access keys: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html
- GitHub SSH setup: https://docs.github.com/en/authentication/connecting-to-github-with-ssh
- ACM DNS validation: https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html
- EKS NetworkPolicy support: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html
