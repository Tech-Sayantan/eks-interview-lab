# Company-Style CI/CD With GitHub Actions, Helm, Environments, And Approvals

This note explains how real teams often move code from a developer laptop to production using branches, pull requests, tests, image scanning, approvals, and Helm deploys.

## The Simple Lab Pipeline We Built

Our lab workflow:

```text
push to main
-> checkout code
-> assume AWS role using GitHub OIDC
-> login to ECR
-> docker build
-> docker push
-> aws eks update-kubeconfig
-> helm lint
-> helm upgrade --install
```

This is good for practice, but real companies usually add more gates.

## Common Branch Model

A simple company model:

```text
feature branch
-> pull request
-> CI checks
-> code review
-> merge to develop
-> deploy to dev environment
-> merge/release to staging
-> integration tests and approval
-> production deployment
```

Example branches:

- `feature/my-change`: developer work
- `develop`: integration branch for dev environment
- `main`: production-ready code
- `release/x.y.z`: optional release stabilization branch
- `hotfix/prod-issue`: emergency fix branch

Not every company uses this exact model. Some use trunk-based development:

```text
short-lived branch
-> PR
-> merge to main
-> progressive deployment
```

Interview line:

"The exact branch model varies, but the important pattern is: review, test, build immutable artifact, promote the artifact, and deploy with approval gates."

## Pull Request Flow

Developer creates a branch:

```bash
git checkout -b feature/add-payment-status
git add .
git commit -m "Add payment status endpoint"
git push origin feature/add-payment-status
```

Then opens a PR into `develop` or `main`.

PR checks usually include:

- unit tests
- linting
- formatting
- type checks
- dependency vulnerability scanning
- SAST
- Dockerfile lint
- Helm lint
- Kubernetes manifest validation
- image build test

Review expectations:

- at least one or two approvals
- no unresolved comments
- all required checks green
- branch up to date with base branch
- no high/critical vulnerabilities unless approved exception

## Environments

Common environments:

- `dev`: fast feedback, lower stability expectations
- `qa`: functional testing
- `staging`: production-like validation
- `prod`: customer-facing

Each environment usually has:

- separate namespace or cluster
- separate Helm values
- separate secrets
- separate AWS account or at least IAM boundary
- separate domain
- separate approvals

Example:

```text
dev.example.com
staging.example.com
app.example.com
```

Production-grade AWS setup often uses separate AWS accounts:

- shared services
- dev
- staging
- prod
- security/logging

## Build Once, Promote Same Image

Best practice:

```text
build image once
scan it
sign it
promote same digest across environments
```

Avoid:

```text
build new image separately for dev, staging, prod
```

Why:

If staging and prod are built separately, you cannot be sure prod is exactly what staging tested.

Better:

```text
image: app@sha256:<digest>
```

or immutable tag:

```text
image: app:<git-sha>
```

In our lab, GitHub Actions used:

```yaml
IMAGE_TAG: ${{ github.sha }}
```

That is good because each commit gets a unique image tag.

## SAST, DAST, Image Scanning, And Dependency Scanning

### SAST

Static Application Security Testing scans source code.

Examples:

- CodeQL
- Semgrep
- SonarQube
- Checkmarx

Finds:

- injection risks
- insecure crypto
- hardcoded secrets
- unsafe deserialization
- path traversal

### Dependency Scanning

Scans packages and lockfiles.

Examples:

- Dependabot
- Snyk
- Trivy filesystem scan
- OWASP Dependency-Check

Finds:

- vulnerable Python packages
- vulnerable npm packages
- vulnerable transitive dependencies

### Container Image Scanning

Scans built image layers.

Examples:

- Trivy image scan
- Grype
- ECR enhanced scanning
- Snyk Container

Finds:

- OS package CVEs
- vulnerable runtime libraries
- secrets accidentally baked into image

### DAST

Dynamic Application Security Testing scans the running app.

Examples:

- OWASP ZAP
- Burp automation

Finds:

- missing security headers
- reflected XSS
- auth/session flaws
- exposed routes

DAST usually runs against dev/staging, not inside every tiny PR.

## Example Company Pipeline

### PR Pipeline

Runs on pull request:

```text
checkout
install dependencies
unit tests
lint
type checks
SAST
dependency scan
Docker build without push
Helm lint
Kubernetes schema validation
```

Purpose:

Catch problems before merge.

### Dev Deploy Pipeline

Runs after merge to `develop`:

```text
build image
scan image
push image to ECR
deploy to dev with Helm
run smoke tests
publish deployment summary
```

### Staging Deploy Pipeline

Runs after release branch or manual approval:

```text
promote image
deploy to staging
run integration tests
run DAST
run migration checks
performance sanity test
```

### Production Deploy Pipeline

Runs after approval:

```text
confirm artifact digest
deploy with Helm
watch rollout
run smoke tests
monitor error rate
enable canary or progressive traffic
rollback if SLO burns
```

## GitHub Actions Environments

GitHub supports deployment environments:

- `dev`
- `staging`
- `production`

Each can have:

- environment variables
- secrets
- required reviewers
- wait timers
- branch restrictions

Example:

```yaml
environment:
  name: production
```

You can require manual approval before production deploy.

## OIDC Instead Of Static AWS Keys

Our pipeline used:

```yaml
permissions:
  id-token: write
  contents: read
```

Then:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}
```

Why this is better:

- no long-lived AWS access keys in GitHub
- token is short-lived
- IAM trust policy can restrict repo, branch, and environment
- easier to revoke

Good trust condition:

```text
repo:Tech-Sayantan/eks-interview-lab:ref:refs/heads/main
```

Production trust can be stricter:

```text
repo:org/repo:environment:production
```

## Helm In CI/CD

Helm deploy command:

```bash
helm upgrade --install interview-app charts/interview-app \
  --namespace interview \
  -f values-prod.yaml \
  --set image.tag="$GITHUB_SHA" \
  --wait \
  --timeout 10m
```

Important flags:

- `upgrade --install`: deploy if missing, upgrade if present
- `--namespace`: target namespace
- `-f`: environment values
- `--set`: runtime values like image tag
- `--wait`: wait for resources to become ready
- `--timeout`: avoid hanging forever

`helm lint` checks chart quality before deployment.

`helm template` renders manifests locally.

`helm diff` shows changes before applying, if plugin is installed.

## Rollback Strategy

Helm rollback:

```bash
helm history interview-app -n interview
helm rollback interview-app <revision> -n interview --wait --timeout 5m
```

Git rollback:

```bash
git revert <bad-commit>
```

Argo CD rollback:

Usually revert Git or sync previous app revision.

Interview answer:

"In Helm-only deployments, I use Helm release history for emergency rollback. In GitOps setups, I prefer reverting Git so desired state remains auditable."

## Canary Deployment

We practiced ALB weighted canary.

Concept:

```text
stable service weight 90
canary service weight 10
ALB forwards weighted traffic
```

Good production canary flow:

```text
deploy canary
send 5 percent traffic
watch metrics
increase to 25 percent
increase to 50 percent
promote to 100 percent
remove old version
```

What to monitor:

- HTTP 5xx
- latency
- error logs
- business metrics
- pod restarts
- CPU/memory
- dependency errors

Tools that do this better:

- Argo Rollouts
- Flagger
- service mesh traffic shifting
- ALB weighted target groups

## Example Improved GitHub Actions Layout

A more complete setup:

```text
.github/workflows/pr-checks.yml
.github/workflows/deploy-dev.yml
.github/workflows/deploy-staging.yml
.github/workflows/deploy-prod.yml
```

PR checks:

```yaml
on:
  pull_request:
    branches: [main, develop]
```

Deploy dev:

```yaml
on:
  push:
    branches: [develop]
```

Deploy prod:

```yaml
on:
  workflow_dispatch:
```

or:

```yaml
on:
  push:
    tags:
      - "v*"
```

## What Happens When A New Developer Joins

They should not get raw cluster-admin by default.

Access pattern:

```text
human identity in IdP or IAM
-> AWS IAM role
-> EKS access entry or aws-auth mapping
-> Kubernetes RBAC Role/ClusterRole
-> RoleBinding/ClusterRoleBinding
```

AWS knows the user through IAM or SSO. Kubernetes authorizes what that identity can do through RBAC.

Example:

```text
AWS IAM role: DeveloperReadOnly
Kubernetes Role: get/list/watch pods, services, deployments
RoleBinding: bind DeveloperReadOnly group to namespace interview
```

Interview line:

"Authentication answers who you are. Authorization answers what you can do. In EKS, AWS IAM authenticates, and Kubernetes RBAC authorizes."

## What To Say In Interview

"A mature pipeline starts with PR checks: tests, lint, SAST, dependency scan, Docker build, Helm lint, and manifest validation. After merge, CI builds one immutable image, scans it, pushes it to ECR, and deploys to lower environments. Promotion to staging and production uses approvals and the same artifact digest. Deployments use Helm or GitOps, with rollout monitoring and rollback strategy. AWS access should use GitHub OIDC, not static keys."

