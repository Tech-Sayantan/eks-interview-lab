# Start Here Today

This is the only file you need to start with today.

Goal for today:

Build one real EKS lab from zero, deploy the app, test it through your domain, practice the important Kubernetes concepts, then destroy the expensive resources.

Tomorrow:

Revise concepts more deeply and practice interview answers.

## How To Follow Me Today

You can lean on me completely for the sequence, commands, explanations, and debugging.

Do not blindly share secrets. Do not paste AWS secret access keys, passwords, MFA codes, GitHub tokens, or credential CSV contents.

For destructive commands like deleting the cluster, I will clearly say what will be destroyed before you run them.

When something fails, send:

```text
I am at Step X.
I ran this command:
<command>

This is the output/error:
<output>
```

I will tell you the next exact action.

## What This Lab Will Include

Yes, the EKS cluster will include the Kubernetes/AWS topics we discussed:

- Dockerized app.
- ECR image repository.
- EKS cluster.
- Self-managed worker nodes.
- Helm deployment.
- Deployment.
- ReplicaSet, created by Deployment.
- Pods.
- ClusterIP Service.
- ALB Ingress.
- AWS Load Balancer Controller.
- Route 53 DNS.
- ACM certificate.
- ConfigMap.
- Secret.
- ServiceAccount.
- IRSA.
- StorageClass.
- PVC.
- PV, dynamically created by EBS CSI.
- StatefulSet.
- Headless Service for Redis.
- DaemonSet.
- ResourceQuota.
- LimitRange.
- HPA.
- NetworkPolicy.
- Startup, liveness, and readiness probes.
- PodDisruptionBudget.
- GitHub Actions OIDC pipeline.

Optional/not required today:

- VPA, because it needs extra CRDs and is better for tomorrow.
- Cluster Autoscaler.
- Argo CD.
- Terraform.
- Full private subnet/NAT Gateway production networking.

## Important Root Account Decision

You can use the AWS root user in the browser for initial account setup, but do not create root access keys.

Use root only for:

- enabling MFA,
- checking billing,
- creating a budget,
- creating one admin IAM user for this lab.

Then use that admin IAM user from your laptop.

This is still fast. It adds around 10 minutes, but avoids a bad habit and protects you if a key leaks. AWS official docs also say not to use the root user for everyday tasks and strongly recommend not creating root access keys.

## Details I Need From You

Send these only:

```text
AWS region:
AWS account ID:
Domain name:
App hostname:
Route 53 hosted zone name:
GitHub username:
GitHub repo name:
Cluster name:
Mac has Homebrew installed? yes/no
Docker Desktop installed/running? yes/no
AWS CLI configured? yes/no
```

Example:

```text
AWS region: ap-south-1
AWS account ID: 123456789012
Domain name: example.com
App hostname: app.example.com
Route 53 hosted zone name: example.com
GitHub username: my-user
GitHub repo name: eks-interview-lab
Cluster name: interview-eks
Mac has Homebrew installed? yes
Docker Desktop installed/running? no
AWS CLI configured? no
```

Do not send:

- AWS root password.
- AWS access key secret.
- GitHub token.
- credential CSV.
- MFA code.

## Step 1: Open The Project

Run:

```bash
cd /Users/sayantanchowdhury/Documents/Codex/2026-07-02/so-amr-ekta-interview-ache-2/outputs/eks-interview-lab
code .
```

If `code .` does not work:

1. Open VS Code manually.
2. Press `Cmd + Shift + P`.
3. Search for `Shell Command: Install 'code' command in PATH`.
4. Run it.
5. Try `code .` again.

## Step 2: AWS Root Browser Setup

In browser:

1. Go to `https://console.aws.amazon.com/`.
2. Sign in as root using the email address used to create the AWS account.
3. If AWS asks you to set up MFA, do it now.
4. After login, click the account name in the top-right corner.
5. Open `Security credentials`.
6. Under `Multi-factor authentication (MFA)`, make sure root MFA is enabled.
7. Search for `Billing and Cost Management`.
8. Open `Budgets`.
9. Create a small monthly budget alert, for example `$10` or `$20`.

Now create the IAM admin user for this lab:

1. Search for `IAM`.
2. Open `IAM`.
3. Left sidebar -> `Users`.
4. Click `Create user`.
5. User name: `eks-lab-admin`.
6. Keep `Provide user access to the AWS Management Console` unchecked unless you also want browser login for this IAM user.
7. Click `Next`.
8. Choose `Attach policies directly`.
9. Search for `AdministratorAccess`.
10. Select `AdministratorAccess`.
11. Click `Next`.
12. Review.
13. Click `Create user`.

Now create CLI access key:

1. Click the new user `eks-lab-admin`.
2. Open the `Security credentials` tab.
3. Scroll to `Access keys`.
4. Click `Create access key`.
5. Choose `Command Line Interface (CLI)`.
6. Tick the confirmation checkbox.
7. Click `Next`.
8. Description tag: `eks interview lab`.
9. Click `Create access key`.
10. Click `Download .csv file`.
11. Store it temporarily somewhere safe.

Do not share that CSV.

After the lab, delete this IAM user or at least delete the access key.

Checkpoint:

You should now have:

- an IAM user named `eks-lab-admin`,
- an access key ID,
- a secret access key,
- root MFA enabled,
- a budget alert.

Stop here if you are unsure. Do not create root access keys.

## Step 3: Configure AWS CLI

Run:

```bash
aws configure --profile eks-lab
```

Enter:

```text
AWS Access Key ID: from CSV
AWS Secret Access Key: from CSV
Default region name: your region, for example ap-south-1
Default output format: json
```

Check:

```bash
aws sts get-caller-identity --profile eks-lab
```

Expected:

You should see your account ID and IAM user ARN.

## Step 4: Install Or Check Tools

Check:

```bash
brew --version
aws --version
eksctl version
kubectl version --client=true
helm version --short
docker version
git --version
```

If Homebrew is missing:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install tools:

```bash
brew install awscli eksctl kubectl helm git jq
brew install --cask docker visual-studio-code
open -a Docker
```

Wait until Docker Desktop is running.

## Step 5: Create GitHub Repo

In browser:

1. Go to GitHub.
2. Create new repository.
3. Name it `eks-interview-lab` or your chosen repo name.
4. Do not initialize README.
5. Keep SSH URL:

```text
git@github.com:<github-username>/<repo-name>.git
```

If SSH is not configured, use `MANUAL_FROM_ZERO_GUIDE.md` Part 5.

## Step 6: Push Code

From project root:

```bash
git init
git add .
git commit -m "Add EKS interview lab"
git branch -M main
git remote add origin git@github.com:<github-username>/<repo-name>.git
git push -u origin main
```

## Step 7: ACM Certificate

In AWS Console:

1. Switch to your chosen region.
2. Go to Certificate Manager.
3. Request public certificate.
4. Domain: your app hostname, for example `app.example.com`.
5. Validation: DNS.
6. Create validation record in Route 53.
7. Wait for status `Issued`.
8. Copy Certificate ARN.

## Step 8: Create EKS Cluster

Create a real config file:

```bash
cp infra/eksctl/cluster-template.yaml infra/eksctl/cluster.yaml
```

Open `infra/eksctl/cluster.yaml` and replace:

```text
__CLUSTER_NAME__
__AWS_REGION__
__K8S_VERSION__
```

Then:

```bash
eksctl create cluster -f infra/eksctl/cluster.yaml --profile eks-lab
```

Then:

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name> --profile eks-lab
kubectl get nodes -o wide
```

## Step 9: Continue With The Manual Guide

After nodes are Ready, continue from:

```text
MANUAL_FROM_ZERO_GUIDE.md
Part 12: Enable NetworkPolicy In VPC CNI
```

Then complete:

- Part 13 metrics-server.
- Part 14 EBS CSI.
- Part 15 AWS Load Balancer Controller.
- Part 16 ECR.
- Part 17 Docker build/push.
- Part 18 app IRSA.
- Part 19 Helm values.
- Part 20 Helm deploy.
- Part 21 Route 53 alias.
- Part 22 practice concepts.
- Part 23 GitHub Actions OIDC.
- Part 25 destroy.

## If You Get Stuck

Send:

```text
I am at START_HERE_TODAY Step X or MANUAL guide Part Y.
Command I ran:
Output/error:
```

I will guide from there.
