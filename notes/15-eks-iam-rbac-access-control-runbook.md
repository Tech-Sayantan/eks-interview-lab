# EKS IAM, Kubernetes RBAC, Access Entries, And Developer Onboarding

This note answers a very common interview question:

```text
A new developer joins the team.
They have an AWS identity.
How do we give them access to the Kubernetes cluster safely?
How does AWS know that this IAM identity and this Kubernetes user are related?
```

The short answer:

```text
AWS IAM authenticates who the person is.
EKS maps that IAM principal into a Kubernetes username and/or groups.
Kubernetes RBAC authorizes what that mapped identity can do.
```

## The Core Mental Model

Do not mix up authentication and authorization.

Authentication answers:

```text
Who are you?
```

Authorization answers:

```text
What are you allowed to do?
```

In EKS, the flow is:

```text
developer
-> AWS credentials or federated login
-> IAM user or IAM role session
-> aws eks get-token
-> Kubernetes API server
-> EKS IAM authenticator
-> Kubernetes username and groups
-> Kubernetes RBAC or EKS access policy
-> allow or deny
```

Interview line:

"In EKS, IAM is usually used for authentication into the cluster, while Kubernetes RBAC is used for authorization inside the cluster. EKS Access Entries are the newer AWS-native way to connect IAM principals to Kubernetes permissions."

## Key Terms

### IAM Principal

An IAM principal is an identity that can make AWS API calls.

Examples:

- IAM user
- IAM role
- assumed-role session
- federated identity assuming a role

For production, prefer roles through IAM Identity Center or another identity provider, not long-lived IAM users.

### IAM Policy

An IAM policy controls AWS API permissions.

Examples:

- allow `eks:DescribeCluster`
- allow `eks:CreateAccessEntry`
- allow `sts:AssumeRole`
- allow `ecr:PutImage`

IAM policy does not directly say whether a person can create Pods inside Kubernetes.

### Kubernetes User

A Kubernetes user is not normally a Kubernetes object.

It is usually just a username string provided by the authentication layer.

Example:

```text
arn:aws:sts::923988301700:assumed-role/EKSDeveloperRole/sayantan
```

### Kubernetes Group

A Kubernetes group is also usually just a string.

Example:

```text
team-a-developers
platform-admins
read-only-auditors
```

RBAC can bind permissions to users, groups, or service accounts.

### ServiceAccount

A Kubernetes ServiceAccount is a real Kubernetes object.

It is mainly for workloads running inside the cluster.

Human access:

```text
IAM principal -> EKS -> Kubernetes user/groups -> RBAC
```

Pod access to AWS:

```text
Pod -> Kubernetes ServiceAccount -> IRSA or EKS Pod Identity -> IAM role -> AWS APIs
```

These two are related but not the same thing.

## Kubernetes RBAC Objects

Kubernetes RBAC has four main objects.

### Role

A `Role` gives permissions inside one namespace.

Example:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-deployer
  namespace: interview
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
```

This says what actions are allowed.

It does not say who receives those permissions.

### RoleBinding

A `RoleBinding` attaches a `Role` or `ClusterRole` to a subject inside one namespace.

Example:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-deployer-binding
  namespace: interview
subjects:
  - kind: Group
    name: interview-developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: app-deployer
  apiGroup: rbac.authorization.k8s.io
```

This means:

```text
Anyone authenticated as group interview-developers
gets the app-deployer Role
inside the interview namespace.
```

### ClusterRole

A `ClusterRole` defines permissions at cluster scope, or reusable permissions that can be applied to many namespaces.

Examples of cluster-scoped resources:

- nodes
- persistentvolumes
- storageclasses
- clusterroles
- clusterrolebindings
- customresourcedefinitions

Example:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: namespace-reader
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch"]
```

### ClusterRoleBinding

A `ClusterRoleBinding` grants a `ClusterRole` across the whole cluster.

Example:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins
subjects:
  - kind: Group
    name: platform-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

Be careful with `ClusterRoleBinding`.

It can grant permissions across every namespace.

## RoleBinding With ClusterRole

This is common and useful.

You can bind a built-in `ClusterRole` like `view`, `edit`, or `admin` inside only one namespace using a `RoleBinding`.

Example:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: interview-edit
  namespace: interview
subjects:
  - kind: Group
    name: interview-developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
```

This means:

```text
interview-developers can edit resources in namespace interview only.
```

It does not make them cluster admins.

## EKS Authentication Methods

EKS supports multiple ways to connect IAM identities to Kubernetes access.

### Modern Method: EKS Access Entries

EKS Access Entries are the recommended method for granting IAM users or roles access to Kubernetes APIs.

An access entry links:

```text
IAM principal ARN
-> Kubernetes username/groups or EKS access policies
```

Example principal:

```text
arn:aws:iam::923988301700:role/EKSDeveloperRole
```

### Legacy Method: aws-auth ConfigMap

Older EKS clusters use the `aws-auth` ConfigMap in `kube-system`.

It maps IAM roles/users to Kubernetes usernames and groups.

Example:

```yaml
mapRoles: |
  - rolearn: arn:aws:iam::923988301700:role/EKSDeveloperRole
    username: developer:{{SessionName}}
    groups:
      - interview-developers
```

Important:

`aws-auth` is deprecated for access management, but many existing companies still use it. For interviews, know both.

## How Does AWS Know The IAM Person And Kubernetes Person Are Same?

AWS does not compare email addresses.

AWS does not look at your laptop username.

AWS checks the AWS identity behind the request.

When you run:

```bash
kubectl get pods -n interview
```

your kubeconfig usually runs something like:

```bash
aws eks get-token --cluster-name interview-eks --region us-east-1
```

The AWS CLI uses your current AWS credentials.

Those credentials may belong to:

- an IAM user
- an assumed IAM role
- an IAM Identity Center session
- a federated SAML/OIDC role session

EKS validates the token and sees the IAM principal ARN.

Then EKS asks:

```text
Is this IAM principal allowed to authenticate to this cluster?
If yes, which Kubernetes username and groups should it become?
```

Then Kubernetes RBAC asks:

```text
Can this username/group perform this verb on this resource in this namespace?
```

Example:

```text
IAM role:
arn:aws:iam::923988301700:role/EKSDeveloperRole

Assumed-role session:
arn:aws:sts::923988301700:assumed-role/EKSDeveloperRole/sayantan

Kubernetes group:
interview-developers

RBAC:
interview-developers can edit deployments in namespace interview
```

That is the bridge.

## Important Audit Detail

If five developers all assume the same IAM role, EKS can map all of them to the same Kubernetes permissions.

To know which human did the action, you need good role session names and identity provider audit trails.

Good:

```text
arn:aws:sts::923988301700:assumed-role/EKSDeveloperRole/sayantan.chowdhury
arn:aws:sts::923988301700:assumed-role/EKSDeveloperRole/alice.mitra
```

Bad:

```text
arn:aws:sts::923988301700:assumed-role/EKSDeveloperRole/session
arn:aws:sts::923988301700:assumed-role/EKSDeveloperRole/session
```

Best practice:

- use IAM Identity Center or corporate IdP
- force unique role session names
- use CloudTrail for AWS-side audit
- enable EKS audit logs for Kubernetes API audit
- avoid shared IAM users
- avoid long-lived access keys for humans

Interview line:

"If everyone shares the same IAM user or undifferentiated role session, audit becomes weak. In production I prefer federated access through IAM Identity Center or an IdP, with users assuming roles and preserving unique session names."

## New Developer Onboarding: Recommended Production Flow

Scenario:

```text
New developer joins team-a.
They need edit access only in namespace team-a-dev.
They should not touch kube-system, production, nodes, IAM, or cluster-wide resources.
```

Recommended flow:

```text
1. Add developer to corporate identity group.
2. That group can assume an IAM role, for example EKSDeveloperRole.
3. Create EKS access entry for that IAM role.
4. Attach namespace-scoped EKS access policy, or map to Kubernetes group.
5. Test with kubectl auth can-i.
6. Log and review access regularly.
```

## Option 1: EKS Access Policy Approach

This is simpler and AWS-native.

Create access entry:

```bash
aws eks create-access-entry \
  --region us-east-1 \
  --cluster-name interview-eks \
  --principal-arn arn:aws:iam::923988301700:role/EKSDeveloperRole \
  --type STANDARD
```

Grant edit access only to a namespace:

```bash
aws eks associate-access-policy \
  --region us-east-1 \
  --cluster-name interview-eks \
  --principal-arn arn:aws:iam::923988301700:role/EKSDeveloperRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=team-a-dev
```

Grant view-only access:

```bash
aws eks associate-access-policy \
  --region us-east-1 \
  --cluster-name interview-eks \
  --principal-arn arn:aws:iam::923988301700:role/EKSReadOnlyRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=namespace,namespaces=team-a-dev
```

Cluster admin access:

```bash
aws eks associate-access-policy \
  --region us-east-1 \
  --cluster-name interview-eks \
  --principal-arn arn:aws:iam::923988301700:role/EKSPlatformAdminRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

Use cluster admin carefully.

This is for platform team or break-glass access, not every developer.

## Option 2: EKS Access Entry Plus Kubernetes RBAC Groups

Use this when you need very custom permissions.

Create access entry and map IAM role to Kubernetes group:

```bash
aws eks create-access-entry \
  --region us-east-1 \
  --cluster-name interview-eks \
  --principal-arn arn:aws:iam::923988301700:role/EKSDeveloperRole \
  --type STANDARD \
  --kubernetes-groups interview-developers
```

Then create Kubernetes RBAC:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-deployer
  namespace: interview
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-deployer-binding
  namespace: interview
subjects:
  - kind: Group
    name: interview-developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: app-deployer
  apiGroup: rbac.authorization.k8s.io
```

This gives very targeted permissions.

## Option 3: Legacy aws-auth ConfigMap

This still exists in many companies.

View current mappings:

```bash
kubectl describe configmap aws-auth -n kube-system
```

or:

```bash
eksctl get iamidentitymapping \
  --cluster interview-eks \
  --region us-east-1
```

Add role mapping with `eksctl`:

```bash
eksctl create iamidentitymapping \
  --cluster interview-eks \
  --region us-east-1 \
  --arn arn:aws:iam::923988301700:role/EKSDeveloperRole \
  --group interview-developers \
  --username developer:{{SessionName}}
```

Then create RoleBinding/ClusterRoleBinding for `interview-developers`.

Warning:

Badly editing `aws-auth` can lock people out. Prefer `eksctl`, Terraform, or controlled automation.

## Enabling Access Entries On Older Clusters

Check access config:

```bash
aws eks describe-cluster \
  --region us-east-1 \
  --name interview-eks \
  --query "cluster.accessConfig"
```

Enable access entries:

```bash
aws eks update-cluster-config \
  --region us-east-1 \
  --name interview-eks \
  --access-config authenticationMode=API_AND_CONFIG_MAP
```

Wait:

```bash
aws eks wait cluster-active \
  --region us-east-1 \
  --name interview-eks
```

Important:

Once you enable an authentication mode that uses the EKS API, AWS says you cannot change back to a mode that removes the EKS API and access entries.

## Connecting With kubectl

Create or update kubeconfig:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name interview-eks
```

If using an assumed role:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name interview-eks \
  --role-arn arn:aws:iam::923988301700:role/EKSDeveloperRole
```

Check current identity:

```bash
aws sts get-caller-identity
```

Check Kubernetes permissions:

```bash
kubectl auth can-i get pods -n interview
kubectl auth can-i create deployments -n interview
kubectl auth can-i delete nodes
kubectl auth can-i get secrets -n interview
```

Check as a specific group if you are admin:

```bash
kubectl auth can-i create deployments \
  -n interview \
  --as-group=interview-developers
```

## Common Interview Scenarios

### "Developer can login to AWS but kubectl says Unauthorized"

Likely causes:

- their IAM identity has no EKS access entry
- their IAM role is not mapped in `aws-auth`
- kubeconfig points to wrong role/profile
- they are authenticated to AWS account A but cluster is in account B
- cluster authentication mode is not configured for access entries

Commands:

```bash
aws sts get-caller-identity
kubectl config current-context
kubectl config view --minify
aws eks list-access-entries --cluster-name interview-eks --region us-east-1
kubectl describe configmap aws-auth -n kube-system
```

### "Developer can list pods but cannot see logs"

The RBAC role may allow `pods` but not `pods/log`.

Need:

```yaml
resources: ["pods/log"]
verbs: ["get"]
```

### "Developer can deploy but cannot create Ingress"

Ingress is in API group `networking.k8s.io`.

Need:

```yaml
apiGroups: ["networking.k8s.io"]
resources: ["ingresses"]
verbs: ["get", "list", "watch", "create", "update", "patch"]
```

### "Developer can do too much"

Check:

```bash
kubectl get rolebinding,clusterrolebinding -A | grep <name-or-group>
kubectl describe rolebinding <name> -n <namespace>
kubectl describe clusterrolebinding <name>
```

Risky bindings:

- `cluster-admin`
- `system:masters`
- broad `ClusterRoleBinding`
- access policies scoped to `cluster` when namespace scope was enough

### "Someone deleted a deployment. Who did it?"

Check:

- EKS audit logs in CloudWatch, if enabled
- CloudTrail for AWS-side access entry changes
- kubectl audit event username
- assumed-role session name
- GitHub Actions logs if deployment came from CI/CD

If all users share one IAM user, attribution is weak.

## IAM Permissions vs Kubernetes Permissions

This is a classic confusion.

IAM permission example:

```json
{
  "Effect": "Allow",
  "Action": [
    "eks:DescribeCluster"
  ],
  "Resource": "*"
}
```

This lets someone call the AWS EKS API.

It does not automatically let them create Pods.

Kubernetes RBAC example:

```yaml
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["create", "update", "patch"]
```

This lets someone perform Kubernetes API operations, after they are authenticated to the cluster.

Interview line:

"IAM controls AWS API permissions. Kubernetes RBAC controls Kubernetes API permissions. EKS access entries bridge the IAM identity into Kubernetes authorization."

## Human Access vs Workload Access

Human access:

```text
developer laptop
-> AWS identity
-> EKS access entry or aws-auth
-> Kubernetes RBAC
-> kubectl permissions
```

Workload access:

```text
pod
-> Kubernetes ServiceAccount
-> IRSA or EKS Pod Identity
-> IAM role
-> AWS service permissions
```

Example from our lab:

The app pod used a Kubernetes ServiceAccount annotated for IRSA so it could read from AWS Secrets Manager/S3-style resources without hardcoding AWS keys.

That is not the same as giving Tan kubectl access to the cluster.

## Practical Access Design

Use groups/roles by job function:

```text
platform-admins
security-auditors
backend-devs
frontend-devs
release-engineers
read-only-support
ci-deployer
```

Avoid:

```text
one IAM user per app
shared admin access keys
everyone in system:masters
manual kubectl edits with no Git history
cluster-admin for normal developers
```

Good namespace model:

```text
team-a-dev
team-a-staging
team-a-prod
platform
observability
```

Example access:

```text
backend-devs:
  edit in team-a-dev
  view in team-a-staging
  no direct prod write

release-engineers:
  deploy in staging/prod
  no cluster-admin

platform-admins:
  cluster-admin through break-glass role
```

## CI/CD Access

GitHub Actions should not use a human IAM user.

Better:

```text
GitHub OIDC
-> assume IAM role
-> EKS access entry for deployer role
-> namespace-scoped deploy permissions
```

In our lab:

```text
GitHub Actions assumed an AWS IAM role through OIDC.
That role pushed to ECR and deployed to EKS with Helm.
Kubernetes access was granted to that IAM role.
```

Production improvement:

- separate build role and deploy role
- use environment protection for production
- require PR approval before deploy
- scope deployer role to namespace
- avoid cluster-admin for CI unless absolutely necessary

## Best Practices

- Prefer IAM Identity Center or federation for humans.
- Prefer IAM roles over IAM users.
- Prefer EKS Access Entries over `aws-auth` for new clusters.
- Use namespace-scoped access where possible.
- Use Kubernetes groups rather than binding individual users everywhere.
- Use `kubectl auth can-i` before and after granting access.
- Enable audit logging for production clusters.
- Keep break-glass admin access separate and monitored.
- Review access regularly.
- Do not grant `system:masters` casually.
- Avoid long-lived access keys for humans.
- Keep access config in Terraform/CloudFormation/CDK where possible.

## Quick Commands

List EKS access entries:

```bash
aws eks list-access-entries \
  --region us-east-1 \
  --cluster-name interview-eks
```

Describe access entry:

```bash
aws eks describe-access-entry \
  --region us-east-1 \
  --cluster-name interview-eks \
  --principal-arn arn:aws:iam::923988301700:role/EKSDeveloperRole
```

List access policies:

```bash
aws eks list-access-policies
```

List associated policies for a principal:

```bash
aws eks list-associated-access-policies \
  --region us-east-1 \
  --cluster-name interview-eks \
  --principal-arn arn:aws:iam::923988301700:role/EKSDeveloperRole
```

List Kubernetes RBAC:

```bash
kubectl get roles,rolebindings -A
kubectl get clusterroles,clusterrolebindings
```

Explain RBAC objects:

```bash
kubectl explain role
kubectl explain rolebinding
kubectl explain clusterrole
kubectl explain clusterrolebinding
```

Check your AWS identity:

```bash
aws sts get-caller-identity
```

Check your Kubernetes permission:

```bash
kubectl auth can-i get pods -n interview
```

## Final Mental Model

Remember this sentence:

```text
IAM proves identity to EKS.
EKS maps identity to Kubernetes username/groups.
RBAC decides what that username/group can do.
```

That one sentence answers most IAM/RBAC/EKS access questions cleanly.

## Sources

- Amazon EKS access entries: https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
- Change authentication mode for EKS access entries: https://docs.aws.amazon.com/eks/latest/userguide/setting-up-access-entries.html
- Create EKS access entries with access policies: https://docs.aws.amazon.com/eks/latest/userguide/create-standard-access-entry-policy.html
- EKS access policy permissions: https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html
- Create EKS access entries using Kubernetes groups: https://docs.aws.amazon.com/eks/latest/userguide/create-k8s-group-access-entry.html
- Set custom username for EKS access entries: https://docs.aws.amazon.com/eks/latest/userguide/set-custom-username.html
- Legacy EKS aws-auth ConfigMap: https://docs.aws.amazon.com/eks/latest/userguide/auth-configmap.html
- Kubernetes RBAC authorization: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
