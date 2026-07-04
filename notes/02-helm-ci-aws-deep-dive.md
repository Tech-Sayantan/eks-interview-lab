# 02 - Helm, CI/CD, And AWS Deep Dive

This chapter explains how we turned raw Kubernetes YAML into a reusable Helm chart, how the GitHub Actions pipeline works, and what AWS services are involved.

## 1. Why Helm Exists

Raw Kubernetes YAML works for small demos, but production apps need:

- Different values per environment.
- Reusable naming conventions.
- Conditional objects.
- Standard labels.
- Repeatable install/upgrade/rollback.
- Release history.

Helm gives:

```text
Chart = package
Values = environment-specific config
Templates = YAML with variables and logic
Release = installed instance of the chart
```

In our lab:

```text
charts/interview-app/
  Chart.yaml
  values.yaml
  templates/
    _helpers.tpl
    deployment.yaml
    service.yaml
    ingress.yaml
    ...
```

## 2. Chart.yaml

File:

```text
charts/interview-app/Chart.yaml
```

Content:

```yaml
apiVersion: v2
name: interview-app
description: A compact EKS, Helm, Kubernetes, and AWS interview practice chart.
type: application
version: 0.1.0
appVersion: "1.0.0"
```

What each field means:

- `apiVersion: v2`: Helm 3 chart format.
- `name`: chart name.
- `description`: human-readable explanation.
- `type: application`: installable app chart.
- `version`: chart version, changes when chart changes.
- `appVersion`: app version metadata, often the app version.

Why `helm lint` says icon is recommended:

Helm charts may include an icon URL. It is optional. For our interview lab it does not matter.

## 3. values.yaml

File:

```text
charts/interview-app/values.yaml
```

Purpose:

Default configuration for the chart.

Example:

```yaml
replicaCount: 2

image:
  repository: ""
  tag: "dev"
  pullPolicy: IfNotPresent

ingress:
  enabled: true
  className: alb
  certificateArn: ""
  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix
```

Why `image.repository` is empty:

Because we do not want the chart to hardcode one AWS account's ECR repo. The real value comes from:

- `manual-values/my-values.yaml` for local manual deploy.
- GitHub Actions generated `/tmp/deploy-values.yaml` for CI/CD deploy.

Interview line:

> `values.yaml` gives sane defaults, but environment-specific values should come from separate values files or pipeline-injected values.

## 4. Local Values vs Chart Defaults

Chart default:

```yaml
image:
  repository: ""
  tag: "dev"
```

Manual values override:

```yaml
image:
  repository: "923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app"
  tag: "manual-v1"
```

GitHub Actions override:

```yaml
image:
  repository: "${IMAGE_REPOSITORY}"
  tag: "${IMAGE_TAG}"
```

Precedence idea:

```text
chart values.yaml
  overridden by -f custom-values.yaml
    overridden by --set key=value
```

Useful command:

```bash
helm get values interview-app -n interview
helm get values interview-app -n interview --all
```

## 5. _helpers.tpl

File:

```text
charts/interview-app/templates/_helpers.tpl
```

This file defines reusable template snippets.

Example:

```gotemplate
{{- define "interview-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Meaning:

- Define a helper named `interview-app.name`.
- Use `.Values.nameOverride` if supplied.
- Otherwise use `.Chart.Name`.
- Truncate to 63 chars because many Kubernetes names must fit DNS label rules.
- Remove trailing `-` if truncation leaves one.

Full name helper:

```gotemplate
{{- define "interview-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}
```

Why this matters:

If release name is `interview-app` and chart name is also `interview-app`, the helper avoids creating `interview-app-interview-app`. It keeps the name clean.

Labels helper:

```gotemplate
{{- define "interview-app.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "interview-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```

Why:

Standard labels make resources easier to query, observe, and operate.

ServiceAccount helper:

```gotemplate
{{- define "interview-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "interview-app.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
```

Meaning:

- If chart creates a ServiceAccount, use configured name or release full name.
- If chart does not create one, use configured name or `default`.

## 6. Helm Template Syntax Used In Our Chart

### `.Values`

Example:

```gotemplate
replicas: {{ .Values.replicaCount }}
```

Means:

Take value from `values.yaml` or override file.

### `.Release.Name`

Example:

```gotemplate
app.kubernetes.io/instance: {{ .Release.Name }}
```

Means:

The installed release name, in our case `interview-app`.

### `.Chart`

Example:

```gotemplate
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
```

Means:

Chart metadata from `Chart.yaml`.

### `include`

Example:

```gotemplate
name: {{ include "interview-app.fullname" . }}
```

Means:

Call a helper template and pass current context `.`.

### `nindent`

Example:

```gotemplate
labels:
  {{- include "interview-app.labels" . | nindent 4 }}
```

Means:

Render helper text and indent it by 4 spaces. YAML is indentation-sensitive, so this matters.

### `toYaml`

Example:

```gotemplate
resources:
  {{- toYaml .Values.resources | nindent 12 }}
```

Means:

Convert a nested values object into valid YAML.

### `required`

Example:

```gotemplate
image: "{{ required "image.repository is required" .Values.image.repository }}:{{ .Values.image.tag }}"
```

Means:

Fail template rendering if `image.repository` is empty. This prevents deploying a broken image reference.

### `if`

Example:

```gotemplate
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}
```

Means:

Only create the object when enabled.

### `with`

Example:

```gotemplate
{{- with .Values.serviceAccount.annotations }}
annotations:
  {{- toYaml . | nindent 4 }}
{{- end }}
```

Means:

If annotations exist, render them. Inside `with`, `.` becomes the annotations map.

### `range`

Example:

```gotemplate
{{- range .Values.ingress.hosts }}
- host: {{ .host | quote }}
{{- end }}
```

Means:

Loop over a list of hosts.

## 7. Converting Raw Manifests To Helm

Start with raw Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: interview-app
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: app
          image: 923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1
```

Helm conversion:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "interview-app.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: app
          image: "{{ required "image.repository is required" .Values.image.repository }}:{{ .Values.image.tag }}"
```

What changed:

- Hardcoded name became helper.
- Hardcoded replica count became value.
- Hardcoded image became value.
- Reusable labels were added.

Raw Ingress:

```yaml
host: app.tanscape.online
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
```

Helm conversion:

```yaml
{{- range .Values.ingress.hosts }}
- host: {{ .host | quote }}
{{- end }}

{{- if .Values.ingress.certificateArn }}
alb.ingress.kubernetes.io/certificate-arn: {{ .Values.ingress.certificateArn | quote }}
{{- end }}
```

What changed:

- Host is configurable.
- Certificate ARN is configurable.
- HTTPS annotations appear only when certificate ARN exists.

Raw Secret:

```yaml
stringData:
  DEMO_API_KEY: demo-change-me
```

Helm conversion:

```yaml
{{- if .Values.secret.create -}}
stringData:
  DEMO_API_KEY: {{ .Values.secret.demoApiKey | quote }}
{{- end }}
```

What changed:

- Secret can be disabled.
- Secret value is configurable.

## 8. Helm Commands In Our Lab

Validate chart:

```bash
helm lint charts/interview-app -f manual-values/my-values.yaml
```

Render locally:

```bash
helm template interview-app charts/interview-app \
  -n interview \
  -f manual-values/my-values.yaml
```

Install/upgrade:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  -f manual-values/my-values.yaml \
  --wait \
  --timeout 10m
```

Status:

```bash
helm status interview-app -n interview
```

History:

```bash
helm history interview-app -n interview
```

Rollback:

```bash
helm rollback interview-app <revision> -n interview
```

Get rendered deployed manifests:

```bash
helm get manifest interview-app -n interview
```

Get values:

```bash
helm get values interview-app -n interview
helm get values interview-app -n interview --all
```

Uninstall:

```bash
helm uninstall interview-app -n interview --wait --timeout 5m
```

Interview line:

> `helm template` shows what would be sent. `helm upgrade --install` actually applies it. `helm lint` catches chart issues before deployment. `helm history` and `helm rollback` support release recovery.

## 9. GitHub Actions Pipeline

File:

```text
.github/workflows/build-deploy.yml
```

Workflow:

```yaml
name: Build and Deploy to EKS

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  id-token: write
  contents: read
```

Meaning:

- Runs on push to `main`.
- Can be manually triggered.
- `id-token: write` is required for GitHub OIDC.
- `contents: read` lets workflow checkout code.

Environment variables:

```yaml
env:
  AWS_REGION: ${{ vars.AWS_REGION || 'ap-south-1' }}
  CLUSTER_NAME: ${{ vars.CLUSTER_NAME || 'interview-eks' }}
  NAMESPACE: ${{ vars.NAMESPACE || 'interview' }}
  HELM_RELEASE: ${{ vars.HELM_RELEASE || 'interview-app' }}
  ECR_REPOSITORY: ${{ vars.ECR_REPOSITORY || 'interview-app' }}
  APP_HOSTNAME: ${{ vars.APP_HOSTNAME }}
  CERTIFICATE_ARN: ${{ vars.CERTIFICATE_ARN }}
  APP_ROLE_ARN: ${{ vars.APP_ROLE_ARN }}
```

These come from GitHub repository variables.

OIDC AWS login:

```yaml
- name: Configure AWS credentials through OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}
```

Meaning:

- GitHub requests OIDC token.
- AWS validates token against IAM role trust policy.
- Workflow gets temporary AWS credentials.
- No AWS access key is stored in GitHub.

ECR login:

```yaml
- name: Login to Amazon ECR
  id: ecr
  uses: aws-actions/amazon-ecr-login@v2
```

Build and push:

```yaml
- name: Build and push image
  env:
    REGISTRY: ${{ steps.ecr.outputs.registry }}
    IMAGE_TAG: ${{ github.sha }}
  run: |
    set -euo pipefail
    IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
    docker build --platform linux/amd64 -t "$IMAGE_URI" app
    docker push "$IMAGE_URI"
    echo "IMAGE_URI=$IMAGE_URI" >> "$GITHUB_ENV"
    echo "IMAGE_REPOSITORY=${REGISTRY}/${ECR_REPOSITORY}" >> "$GITHUB_ENV"
    echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_ENV"
```

Important points:

- Image tag is Git commit SHA. This is traceable.
- `--platform linux/amd64` avoids architecture surprises.
- Outputs are written to `$GITHUB_ENV` for later steps.

Configure kubeconfig:

```yaml
- name: Configure kubeconfig
  run: aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
```

Meaning:

- Sets kubeconfig context for EKS cluster.
- The AWS role still needs EKS/Kubernetes authorization.

Deploy with Helm:

```yaml
- name: Deploy with Helm
  run: |
    set -euo pipefail
    cat > /tmp/deploy-values.yaml <<YAML
    image:
      repository: "${IMAGE_REPOSITORY}"
      tag: "${IMAGE_TAG}"
    config:
      appEnv: "eks"
      appMessage: "deployed by GitHub Actions OIDC"
    ingress:
      certificateArn: "${CERTIFICATE_ARN}"
      hosts:
        - host: "${APP_HOSTNAME}"
          paths:
            - path: /
              pathType: Prefix
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "${APP_ROLE_ARN}"
    YAML

    helm lint charts/interview-app -f /tmp/deploy-values.yaml
    helm upgrade --install "$HELM_RELEASE" charts/interview-app \
      --namespace "$NAMESPACE" \
      -f /tmp/deploy-values.yaml \
      --wait \
      --timeout 10m
```

Why generate values inside pipeline:

- The pipeline knows the image tag after build.
- It injects runtime-specific details.
- It avoids committing account-specific values to the repo.

Real issues we fixed:

1. OIDC trust policy mismatch:

```text
Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

Cause:

- IAM trust policy did not allow the exact GitHub repo/ref subject.

Fix:

- Adjust trust policy to allow the branch/ref used by the workflow.

2. StorageClass permission:

```text
storageclasses.storage.k8s.io "interview-gp3" is forbidden
```

Cause:

- `StorageClass` is cluster-scoped.
- Role had enough namespace access for app objects but not enough cluster scope.

Fix:

- Add appropriate EKS access policy at cluster scope.

Interview line:

> CI/CD to EKS needs both AWS IAM permissions and Kubernetes authorization. Passing AWS OIDC authentication is only half the path.

## 10. CI/CD Design Considerations

Good production pipeline usually includes:

- Build.
- Unit tests.
- Static analysis.
- Dependency scan.
- Container image scan.
- Push immutable image tag.
- Render Helm.
- Lint Helm.
- Deploy to non-prod.
- Run smoke tests.
- Promote the same image to prod.
- Use approvals for prod.
- Rollback plan.

Important security points:

- Use OIDC, not long-lived AWS keys.
- Restrict trust policy by repo/branch/environment.
- Use least privilege.
- Avoid printing secrets.
- Use immutable image tags, preferably commit SHA or digest.
- Consider signing images.

Important deployment points:

- `--wait` catches readiness failures.
- Helm rollback can recover chart release.
- Kubernetes rollout history can track Deployment ReplicaSets.
- Smoke test after deploy should hit `/healthz`, `/readyz`, and important business endpoints.

Example smoke test step:

```yaml
- name: Smoke test
  run: |
    set -euo pipefail
    curl -fsS "https://${APP_HOSTNAME}/healthz"
    curl -fsS "https://${APP_HOSTNAME}/readyz"
```

## 11. AWS Services In This Lab

### IAM

Used for:

- IAM user used from your laptop.
- EKS node role.
- EBS CSI driver role.
- AWS Load Balancer Controller role.
- App IRSA role.
- GitHub Actions OIDC deployer role.

Interview line:

> On EKS, IAM and Kubernetes RBAC/authorization both matter. IAM controls AWS API access; Kubernetes authorization controls Kubernetes API access.

### EKS

AWS manages:

- API server.
- etcd.
- control plane HA.

You manage:

- worker nodes.
- add-ons.
- IAM.
- networking.
- storage.
- workloads.
- upgrades and version skew.

Self-managed node group:

- EC2 instances are managed through eksctl/CloudFormation.
- You have more responsibility than managed node groups.
- Good interview point: node upgrades, AMI updates, draining, capacity, and replacement are your concern.

### VPC

Network boundary for cluster.

Objects involved:

- VPC.
- public subnets.
- route tables.
- internet gateway.
- security groups.
- ENIs.

Cost choice:

- We used public nodes to avoid NAT Gateway cost for short lab.
- Production usually uses private nodes plus NAT Gateway or VPC endpoints.

### Amazon VPC CNI

Purpose:

- Assigns VPC IPs to pods.
- Integrates pods with AWS networking.
- Can enforce NetworkPolicy when enabled.

Real issue:

- NetworkPolicy support required correct CNI/node permissions.

### EBS CSI Driver

Purpose:

- Allows Kubernetes to dynamically provision EBS volumes.

Objects:

- EBS CSI controller.
- EBS CSI node plugin.
- StorageClass.
- PVC.
- PV.
- EBS volume in AWS.

Common issue:

- IAM permission missing.
- Volume in wrong AZ.
- Pod cannot write due to Linux permissions/security context.

### AWS Load Balancer Controller

Purpose:

- Watches Ingress and Service resources.
- Creates ALB/NLB resources in AWS.

For our Ingress, it created:

- ALB.
- listeners.
- listener rules.
- target group.
- target registration.
- security group changes.
- TargetGroupBinding in Kubernetes.

### ACM

Purpose:

- TLS certificate for `app.tanscape.online`.

Important:

- For ALB in `us-east-1`, certificate must be in `us-east-1`.
- DNS validation through Route 53.

### Route 53

Purpose:

- Hosted zone for `tanscape.online`.
- Alias A record for `app.tanscape.online` pointing to ALB.

Important:

- Alias record points to AWS resource.
- DNS can take time to propagate.

### ECR

Purpose:

- Stores Docker image.

Manual push:

```bash
aws ecr get-login-password --region us-east-1 --profile eks-lab \
  | docker login --username AWS --password-stdin 923988301700.dkr.ecr.us-east-1.amazonaws.com

docker build --platform linux/amd64 \
  -t 923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1 \
  app

docker push 923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1
```

Where credentials came from:

- AWS CLI used your `eks-lab` profile.
- AWS returned temporary ECR auth token.
- Docker used that token for registry login.

### S3

Purpose:

- Demo bucket for app IRSA role.
- Even if app currently only calls STS, the role/bucket setup demonstrates how pod-specific AWS permissions would work.

## 12. AWS Troubleshooting Stories From Our Lab

### OIDC Trust

Symptom:

```text
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

Thought process:

1. Does workflow have `id-token: write`?
2. Does role trust GitHub OIDC provider?
3. Does trust policy `aud` equal `sts.amazonaws.com`?
4. Does trust policy `sub` match repo and branch?

### EKS Authorization

Symptom:

```text
cannot get resource storageclasses at cluster scope
```

Thought process:

1. AWS role was assumed successfully.
2. EKS API was reachable.
3. Kubernetes authorization failed.
4. Resource is cluster-scoped, not namespace-scoped.

### EBS/Redis

Symptom:

```text
Redis pod failed even though PVC was Bound
```

Thought process:

1. PVC Bound means volume provisioning worked.
2. Pod logs showed write/permission issue.
3. Fix was at container/security context layer.

Good interview story:

> I separate cloud provisioning from pod runtime behavior. A Bound PVC tells me the volume exists, not that the application can write to it.

## 13. Production Checklist

For a real production EKS app, think about:

- Private nodes.
- NAT Gateway or VPC endpoints.
- Managed node groups or Karpenter.
- Cluster Autoscaler/Karpenter.
- External Secrets.
- AWS WAF in front of ALB.
- TLS policy.
- Access logs.
- Container image scanning.
- Resource requests/limits.
- Pod anti-affinity/topology spread.
- PDB.
- HPA.
- Observability: logs, metrics, traces.
- Alerts.
- Backup/restore for stateful data.
- Runbooks.
- Upgrade plan.
- Least privilege IAM.
- GitOps or controlled CI/CD promotion.

## 14. Interview Explanation In 90 Seconds

Use this answer:

> I built a hands-on EKS lab with a Dockerized FastAPI app deployed through Helm. The app runs as a Deployment behind a ClusterIP Service and is exposed publicly through ALB Ingress with ACM TLS and Route 53 DNS. It uses Redis as a StatefulSet with an EBS-backed PVC through the EBS CSI driver. I added ConfigMap, Secret, ServiceAccount with IRSA, HPA, probes, ResourceQuota, LimitRange, PDB, DaemonSet, and NetworkPolicy. CI/CD runs from GitHub Actions using OIDC to assume an AWS role, builds and pushes to ECR, then deploys using Helm. During the lab I debugged real issues: GitHub OIDC trust mismatch, cluster-scoped StorageClass permission, and Redis volume permission failures.

