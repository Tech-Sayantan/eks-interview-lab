# EKS Cluster Upgrade Runbook

This note explains how to upgrade an Amazon EKS cluster safely: what to check before the upgrade, the correct order, the commands, failure scenarios, and what to say in an interview.

## Mental Model

An EKS upgrade is not one action. It is a sequence:

```text
prepare and audit
-> upgrade control plane
-> upgrade cluster add-ons
-> upgrade worker nodes
-> validate workloads
-> clean up deprecated APIs and old versions
```

The control plane is managed by AWS, but worker nodes, add-ons, Helm apps, storage drivers, ingress controllers, and application manifests are still your responsibility.

## Upgrade Order

Use this order:

1. Read release notes and check deprecated APIs.
2. Check cluster health.
3. Back up important manifests and persistent data.
4. Upgrade control plane by one minor version.
5. Upgrade EKS add-ons.
6. Upgrade worker nodes.
7. Restart or roll workloads where needed.
8. Validate apps, HPA, Ingress, storage, IRSA, and monitoring.

Important rule:

Amazon EKS control plane upgrades happen one minor version at a time. For example, do `1.32 -> 1.33 -> 1.34`, not `1.32 -> 1.34` directly.

## Why Upgrade Carefully

Kubernetes upgrades can break workloads because of:

- removed API versions
- controller compatibility issues
- add-on compatibility issues
- kubelet/control-plane version skew
- admission webhook failures
- pod disruption budgets blocking node replacement
- old Helm charts rendering deprecated APIs
- node AMI/runtime changes
- CNI, CoreDNS, kube-proxy, or CSI driver changes

Interview line:

"I treat Kubernetes upgrades as a compatibility and rollout exercise, not just a version bump."

## Phase 1: Pre-Upgrade Audit

### Check Versions

```bash
aws eks describe-cluster \
  --region us-east-1 \
  --name interview-eks \
  --query 'cluster.version' \
  --output text

kubectl version --short
kubectl get nodes -o wide
```

What you are checking:

- current control plane version
- local kubectl version
- kubelet version on each node
- whether nodes are already behind

Concept:

Version skew means different Kubernetes components can temporarily run different versions, but only within supported limits.

### Check Upgrade Insights

EKS has upgrade insights for compatibility risks.

```bash
aws eks list-insights \
  --region us-east-1 \
  --cluster-name interview-eks

aws eks describe-insight \
  --region us-east-1 \
  --cluster-name interview-eks \
  --id <insight-id>
```

Use this to find possible upgrade blockers like deprecated API usage.

### Check Deprecated APIs

Commands:

```bash
kubectl api-resources --verbs=list --namespaced -o name
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis || true
```

Useful tools:

- `kubent`
- `pluto`
- EKS upgrade insights
- CI checks against rendered Helm manifests

For Helm charts:

```bash
helm template interview-app charts/interview-app -f values.yaml > rendered.yaml
kubectl apply --dry-run=server -f rendered.yaml
```

Why:

If your manifests use APIs removed in the target Kubernetes version, the upgrade may complete but future deploys can fail.

### Check Workload Health

```bash
kubectl get pods -A
kubectl get nodes
kubectl get deploy,sts,ds,hpa,pdb -A
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
```

Do not start an upgrade when the cluster is already unhealthy unless the upgrade is required to fix that exact issue.

### Check Add-ons

```bash
aws eks list-addons \
  --region us-east-1 \
  --cluster-name interview-eks

aws eks describe-addon \
  --region us-east-1 \
  --cluster-name interview-eks \
  --addon-name vpc-cni
```

Important add-ons:

- VPC CNI
- CoreDNS
- kube-proxy
- EBS CSI driver
- AWS Load Balancer Controller, if installed by Helm
- metrics-server

### Check PDBs

```bash
kubectl get pdb -A
```

Why:

Node upgrades and drains use evictions. PDBs can block node replacement if they allow no disruptions.

This happened during our teardown with kube-system PDBs.

## Phase 2: Backup

For a serious environment:

```bash
kubectl get all -A -o yaml > cluster-workloads-backup.yaml
kubectl get configmap,secret,sa,role,rolebinding,clusterrole,clusterrolebinding -A -o yaml > cluster-rbac-config-backup.yaml
kubectl get pvc,pv,storageclass -A -o yaml > cluster-storage-backup.yaml
```

For persistent data:

- take EBS snapshots
- confirm database backups
- confirm restore procedure
- document owner and RTO/RPO

Interview line:

"Before upgrades, I confirm both control-plane compatibility and application/data rollback options."

## Phase 3: Upgrade Control Plane

Using `eksctl`:

```bash
eksctl upgrade cluster \
  --name interview-eks \
  --region us-east-1 \
  --version 1.35 \
  --approve
```

Using AWS CLI:

```bash
aws eks update-cluster-version \
  --region us-east-1 \
  --name interview-eks \
  --kubernetes-version 1.35
```

Wait:

```bash
aws eks describe-update \
  --region us-east-1 \
  --name interview-eks \
  --update-id <update-id>
```

What happens:

- AWS upgrades the managed control plane
- API server remains highly available
- worker nodes are not automatically upgraded
- your workloads keep running on existing nodes

Important:

You generally cannot downgrade an EKS control plane after upgrade.

## Phase 4: Upgrade Add-ons

Check available versions:

```bash
aws eks describe-addon-versions \
  --region us-east-1 \
  --kubernetes-version 1.35 \
  --addon-name vpc-cni
```

Update managed add-ons:

```bash
aws eks update-addon \
  --region us-east-1 \
  --cluster-name interview-eks \
  --addon-name vpc-cni \
  --resolve-conflicts OVERWRITE

aws eks update-addon \
  --region us-east-1 \
  --cluster-name interview-eks \
  --addon-name coredns \
  --resolve-conflicts OVERWRITE

aws eks update-addon \
  --region us-east-1 \
  --cluster-name interview-eks \
  --addon-name kube-proxy \
  --resolve-conflicts OVERWRITE

aws eks update-addon \
  --region us-east-1 \
  --cluster-name interview-eks \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts OVERWRITE
```

Validate:

```bash
kubectl rollout status daemonset/aws-node -n kube-system --timeout=180s
kubectl rollout status deployment/coredns -n kube-system --timeout=180s
kubectl rollout status daemonset/kube-proxy -n kube-system --timeout=180s
kubectl rollout status deployment/ebs-csi-controller -n kube-system --timeout=180s
```

Helm-managed add-ons:

```bash
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --reuse-values
```

Concept:

Add-ons are cluster-critical. If CNI breaks, pods cannot network correctly. If CoreDNS breaks, service discovery breaks. If EBS CSI breaks, StatefulSets using PVCs can fail.

## Phase 5: Upgrade Worker Nodes

### Managed Node Group

If using managed node groups:

```bash
eksctl upgrade nodegroup \
  --cluster interview-eks \
  --region us-east-1 \
  --name <nodegroup-name> \
  --kubernetes-version 1.35
```

or:

```bash
aws eks update-nodegroup-version \
  --region us-east-1 \
  --cluster-name interview-eks \
  --nodegroup-name <nodegroup-name> \
  --kubernetes-version 1.35
```

### Self-Managed Node Group

Our lab used a self-managed node group.

Common safe approach:

1. Create a new node group with the new Kubernetes AMI/version.
2. Wait for new nodes to join.
3. Cordon old nodes.
4. Drain old nodes.
5. Validate workloads on new nodes.
6. Delete old node group.

Commands:

```bash
kubectl get nodes -o wide

kubectl cordon <old-node>

kubectl drain <old-node> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=10m
```

Then remove old ASG/node group through `eksctl`, CloudFormation, Terraform, or console depending on how it was created.

Why blue/green nodes are safer:

- avoids in-place surprises
- lets you test scheduling on new nodes
- easier rollback by keeping old node group temporarily

## Phase 6: Validate After Upgrade

Core checks:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
kubectl top nodes
kubectl top pods -A
```

App checks:

```bash
curl -i https://app.example.com/healthz
curl -i https://app.example.com/readyz
curl -i https://app.example.com/
```

Ingress checks:

```bash
kubectl get ingress -A
kubectl get targetgroupbinding -A
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

Storage checks:

```bash
kubectl get pvc,pv -A
kubectl get volumeattachment
kubectl describe pod <stateful-pod> -n <namespace>
```

IRSA checks:

```bash
kubectl get sa -A -o yaml | grep eks.amazonaws.com/role-arn -n
curl -fsS https://app.example.com/aws/identity
curl -fsS https://app.example.com/secret-manager-check
```

HPA checks:

```bash
kubectl get hpa -A
kubectl top pods -A
```

## Common Failure Scenarios

### Deprecated API Breaks Deployments

Symptom:

```text
no matches for kind "Ingress" in version "extensions/v1beta1"
```

Cause:

Manifest uses removed API.

Fix:

- update chart/manifests
- use supported API version
- run server-side dry-run before upgrade

### PDB Blocks Node Drain

Symptom:

```text
Cannot evict pod as it would violate the pod's disruption budget
```

Cause:

Too few replicas or too strict PDB.

Fix:

- temporarily scale replicas up
- adjust PDB
- upgrade during maintenance window
- for teardown only, delete PDB

### CoreDNS Fails After Upgrade

Symptoms:

- services cannot resolve DNS
- app cannot connect to `redis.default.svc`
- `nslookup` fails from debug pod

Commands:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system deployment/coredns
kubectl describe deployment coredns -n kube-system
```

Fix:

- upgrade CoreDNS add-on
- check node capacity
- check PDB
- check CoreDNS configmap

### CNI Issue After Upgrade

Symptoms:

- pods stuck `ContainerCreating`
- no pod IP assigned
- network timeouts
- `aws-node` not ready

Commands:

```bash
kubectl get ds aws-node -n kube-system
kubectl logs -n kube-system daemonset/aws-node
kubectl describe node <node>
```

Fix:

- update VPC CNI
- check IAM permissions
- check IP exhaustion
- check subnet free IPs

### EBS CSI Issue

Symptoms:

- PVC pending
- pod stuck mounting volume
- StatefulSet unavailable
- `VolumeAttachment` stuck

Commands:

```bash
kubectl get pvc,pv,volumeattachment -A
kubectl logs -n kube-system deployment/ebs-csi-controller
kubectl describe pod <stateful-pod> -n <ns>
```

Fix:

- update EBS CSI add-on
- check CSI controller IAM role
- check EBS volume AZ
- check node availability in same AZ

### Webhook Breaks API Operations

Symptoms:

- apply/upgrade fails
- timeout calling webhook
- resources cannot be created

Cause:

Admission webhook service is unavailable or incompatible.

Commands:

```bash
kubectl get validatingwebhookconfiguration
kubectl get mutatingwebhookconfiguration
kubectl get svc -A | grep webhook
```

Fix:

- upgrade webhook controller
- restore webhook service
- temporarily adjust failure policy only with caution

### Node Version Skew Problem

Symptoms:

- nodes not supported with new control plane
- kubelet too old
- unexpected scheduling/runtime issues

Fix:

- follow Kubernetes version skew policy
- upgrade nodes after control plane
- avoid leaving nodes too far behind

## Rollback Thinking

Control plane:

- EKS control plane downgrade is generally not available.
- Rollback strategy is preparation, compatibility checks, and fixing forward.

Add-ons:

- can often roll back add-on versions, but test compatibility.

Nodes:

- blue/green node groups provide practical rollback.
- keep old node group briefly until validation passes.

Applications:

- Helm rollback or Git revert.

Data:

- snapshots/backups are the rollback.

Interview line:

"For EKS upgrades, rollback is mostly about application rollback and node-group rollback. Control plane upgrades are usually fix-forward, so pre-checks are critical."

## Production Upgrade Checklist

Use this checklist:

- Confirm target version is supported by EKS.
- Read EKS and Kubernetes release notes.
- Check EKS upgrade insights.
- Check deprecated APIs.
- Update local `kubectl`, `eksctl`, and AWS CLI.
- Check cluster health.
- Confirm backups.
- Confirm PDBs will allow disruption.
- Upgrade control plane one minor version.
- Upgrade add-ons.
- Upgrade worker nodes.
- Validate apps.
- Monitor metrics, logs, and alerts.
- Keep old node group temporarily if using blue/green.
- Document outcome.

## Mock Interview Answer

"I upgrade EKS in phases. First I check upgrade insights, deprecated APIs, version skew, cluster health, PDBs, and backups. Then I upgrade the control plane one minor version at a time. After that I upgrade critical add-ons like VPC CNI, CoreDNS, kube-proxy, and EBS CSI. Then I upgrade nodes, preferably with a blue/green node group strategy for safer rollback. Finally I validate workloads, ingress, storage, HPA, IRSA, and monitoring. I treat control plane rollback as mostly fix-forward, so pre-upgrade checks are very important."

## Sources

- AWS EKS: Update existing cluster to new Kubernetes version: https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html
- AWS EKS: Best Practices for Cluster Upgrades: https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html
- AWS EKS: Amazon EKS add-ons: https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html
- AWS EKS: Kubernetes version lifecycle: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- Kubernetes: Version Skew Policy: https://kubernetes.io/releases/version-skew-policy/
- Kubernetes: Deprecated API Migration Guide: https://kubernetes.io/docs/reference/using-api/deprecation-guide/

