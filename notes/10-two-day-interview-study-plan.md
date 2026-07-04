# Two-Day Interview Study Plan

This is the focused plan now that the cluster is being torn down. You do not need the live cluster to revise these concepts.

## How To Study

Read in this order:

1. `06-today-lab-retrospective.md`
2. `09-kubernetes-production-troubleshooting-playbook.md`
3. `07-eks-cluster-creation-networking-dns-deep-dive.md`
4. `08-company-style-github-actions-cicd.md`
5. earlier notes: manifests, Helm, AWS networking, canary

Goal:

You should be able to explain each topic without memorizing exact YAML.

## Day 1: Kubernetes And EKS Core

### Kubernetes Objects

Revise:

- Pod
- Deployment
- ReplicaSet
- Service
- Ingress
- ConfigMap
- Secret
- ServiceAccount
- StatefulSet
- DaemonSet
- PVC/PV/StorageClass
- HPA
- PDB
- NetworkPolicy
- ResourceQuota
- LimitRange

For each object, answer:

- what problem does it solve?
- who creates it?
- who consumes it?
- what are common failure modes?
- what command shows its state?

### Commands To Memorize

```bash
kubectl get pods -A
kubectl get pods -n <ns> -o wide
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
kubectl get events -n <ns> --sort-by=.lastTimestamp
kubectl get deploy,rs,svc,endpoints,ingress -n <ns>
kubectl rollout status deployment/<name> -n <ns>
kubectl rollout history deployment/<name> -n <ns>
kubectl top pods -n <ns>
kubectl top nodes
```

### Must-Know Distinctions

Pod `Running` vs `Ready`:

`Running` means the container process exists. `Ready` means the pod is eligible for Service traffic.

Deployment vs StatefulSet:

Deployment manages replaceable stateless pods. StatefulSet gives stable identity and stable storage.

ConfigMap vs Secret:

Both inject config. Secret is intended for sensitive values but is only base64 encoded by default; use encryption at rest and external secret systems for stronger security.

Liveness vs Readiness:

Liveness restarts containers. Readiness controls traffic.

Service vs Ingress:

Service is internal stable networking. Ingress exposes HTTP/S routing through a controller.

Security Group vs NetworkPolicy:

Security Group is AWS ENI-level. NetworkPolicy is Kubernetes pod-level.

IAM vs RBAC:

IAM authenticates AWS identities and authorizes AWS API actions. Kubernetes RBAC authorizes Kubernetes API actions.

## Day 1: Troubleshooting Practice Without Cluster

Take each symptom and speak the debug flow aloud:

### App Returns 503

Say:

"I check Ingress and ALB target health, then Service endpoints, pod readiness, probes, logs, and dependency health."

### Pod Pending

Say:

"I describe the pod and read scheduler events. I check CPU/memory, taints, node selectors, PVC binding, PV node affinity, quota, and pod density."

### CrashLoopBackOff

Say:

"I inspect logs and previous logs, describe pod events, command/args, env vars, config, secrets, and startup dependencies."

### ImagePullBackOff

Say:

"I check image tag, registry URL, ECR auth, node IAM permissions, network egress, and architecture."

### HPA Not Scaling

Say:

"I check metrics-server, CPU requests, HPA target, actual pod CPU, workload type, and stabilization delays."

## Day 2: AWS, CI/CD, And Scenario Answers

### EKS Creation

Revise:

- control plane
- node groups
- VPC/subnets
- route tables
- internet gateway
- NAT Gateway
- security groups
- NACL
- IAM roles
- OIDC provider
- EKS add-ons

Be able to explain:

```text
eksctl created the control plane, VPC, public subnets, route tables, IGW, security groups, and self-managed worker node group. Add-ons included VPC CNI, CoreDNS, kube-proxy, metrics-server, EBS CSI, and AWS Load Balancer Controller.
```

### AWS Load Balancer Controller

Say:

"The controller watches Ingress objects and creates ALB resources in AWS: load balancer, listener, target groups, rules, and TargetGroupBinding resources."

### EBS CSI

Say:

"The EBS CSI driver provisions EBS volumes for PVCs. EBS is AZ-scoped, so pods using that PV must schedule onto a node in the same AZ."

### IRSA

Say:

"IRSA maps a Kubernetes service account to an IAM role using the cluster OIDC provider. The pod gets a projected token and calls STS AssumeRoleWithWebIdentity for temporary credentials."

### GitHub Actions OIDC

Say:

"GitHub Actions does not store AWS keys. It requests an OIDC token and assumes an AWS role whose trust policy allows that repo/branch/environment."

## Company Pipeline Revision

Memorize this flow:

```text
developer branch
-> pull request
-> tests/lint/SAST/dependency scan
-> review approval
-> merge
-> build immutable image
-> image scan
-> deploy to dev
-> integration tests
-> approval to staging/prod
-> Helm or GitOps deploy
-> rollout monitoring
-> rollback if needed
```

Be ready for:

- "How do you deploy?"
- "How do you rollback?"
- "How do you secure AWS credentials?"
- "How do you prevent bad code reaching prod?"
- "What happens if someone manually changes the cluster?"

## Topics To Brush Up Separately

### Cluster Autoscaler vs HPA vs VPA

HPA changes pod replica count.

VPA changes pod resource requests.

Cluster Autoscaler changes node count.

Karpenter provisions nodes more dynamically based on pending pods.

### Requests And Limits

Requests affect scheduling and HPA percentage.

Limits cap resource usage.

CPU throttling can happen when CPU limit is too low.

Memory limit breach causes OOMKill.

### OOMKilled

Debug:

```bash
kubectl describe pod <pod>
kubectl top pod <pod>
kubectl logs <pod> --previous
```

Fix:

- find memory leak
- raise memory limit
- tune JVM/runtime
- reduce workload

### TLS And DNS

Know:

- Route 53 hosted zone
- DNS delegation from GoDaddy
- ACM DNS validation
- ALB HTTPS listener
- alias record to ALB

### Secrets

Know:

- Kubernetes Secret
- AWS Secrets Manager
- External Secrets Operator concept
- IRSA permission for secret retrieval
- never print secret values

## Mock Interview Answers

### Explain Your Project

"I built an EKS interview lab on AWS with a Dockerized FastAPI app deployed through Helm. The app was exposed through ALB Ingress, Route 53, and ACM. It used Redis as a StatefulSet with EBS-backed persistent storage, IRSA to access AWS Secrets Manager, and GitHub Actions OIDC for CI/CD. I also practiced HPA, NetworkPolicy, PDB, DaemonSet, ResourceQuota, LimitRange, canary traffic splitting, Helm rollback, and several production-style failures."

### How Would You Debug Production Down?

"I start outside-in. First DNS and TLS, then ALB/Ingress, then Service endpoints, then pod readiness, logs, and events. If pods are pending, I check scheduling constraints, node capacity, taints, quota, and PVC node affinity. If pods are crashing, I check logs and previous logs. If dependencies fail, I validate Redis, Secrets Manager, and IRSA."

### What Was The Hardest Issue You Saw?

"Redis became pending after a node drain because its EBS volume was tied to `us-east-1d`, and the only node in that AZ had reached pod capacity. The app pods were running but not ready because readiness depended on Redis. The fix was to free pod slots on the correct AZ node so Redis could schedule and attach its EBS volume."

### Why Helm?

"Helm packages Kubernetes manifests into reusable charts with values per environment. It gives release history, templating, and rollback. It is good for teams that want consistent Kubernetes deployment without writing raw manifests every time."

### Why Not Put Redis In Liveness?

"If Redis goes down, restarting app pods may not help. Readiness should fail so traffic is removed. Liveness should usually detect stuck or dead app processes, not every downstream dependency failure."

## Final Two-Day Focus

Spend your limited time like this:

- 40 percent Kubernetes troubleshooting
- 25 percent EKS/AWS networking/storage/IAM
- 20 percent CI/CD and Helm
- 15 percent scenario practice and mock answers

Most interviewers care less about perfect syntax and more about whether you can reason clearly under failure.

