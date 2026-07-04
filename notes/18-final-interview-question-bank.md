# Final Interview Question Bank And Answer Patterns

This is the last-mile revision note.

Use it when you are tired and want direct interview-style prompts.

The goal is not to memorize every word. The goal is to practice calm, structured answers.

## Your Project Pitch

Use this when they ask:

```text
Tell me about a Kubernetes/AWS project you worked on.
```

Answer:

"I built a hands-on EKS interview lab on AWS. The app was a containerized FastAPI service deployed with Helm to EKS. It used ALB Ingress with Route 53 and ACM, Redis as a StatefulSet with EBS-backed PVC, ConfigMap and Secret, IRSA for AWS access, HPA, NetworkPolicy, ResourceQuota, LimitRange, DaemonSet, probes, and GitHub Actions OIDC for CI/CD. I also practiced canary traffic splitting with ALB weighted target groups, Helm rollback, CrashLoopBackOff, ImagePullBackOff, Redis dependency failure, PDB/node drain behavior, and full cost-safe teardown."

Then stop.

Let them ask follow-up questions.

## Answer Formula

For troubleshooting:

```text
Symptom
-> layer
-> command
-> likely cause
-> safe fix
-> prevention
```

For design:

```text
requirement
-> constraints
-> tradeoffs
-> chosen design
-> failure handling
-> observability
-> cost/security
```

## Docker Questions

### Image vs container?

Image is immutable packaged filesystem plus metadata. Container is a running process created from that image with isolation and a writable layer.

### CMD vs ENTRYPOINT?

`ENTRYPOINT` defines the executable contract. `CMD` provides default arguments or default command. In Kubernetes, `command` overrides ENTRYPOINT and `args` overrides CMD.

### Why not use `latest`?

Because it is mutable. It makes deployments non-reproducible and rollbacks unreliable. Prefer Git SHA tags or digests.

### Why non-root container?

It reduces blast radius if the app is compromised. It is one layer in a defense-in-depth container security model.

### Why ImagePullBackOff?

Wrong image tag, missing ECR image, bad registry auth, node IAM lacks ECR pull, wrong region/account, network path to ECR broken, or architecture mismatch.

## Kubernetes Object Questions

### Deployment vs StatefulSet?

Deployment manages interchangeable stateless Pods. StatefulSet gives stable identity, stable network name, ordered rollout, and usually stable PVC per replica.

### Service vs Ingress?

Service provides stable internal access to Pods. Ingress defines HTTP/HTTPS routing and needs a controller. On AWS, AWS Load Balancer Controller turns Ingress into ALB resources.

### ConfigMap vs Secret?

ConfigMap stores non-sensitive config. Secret stores sensitive values, but Kubernetes Secrets are only base64 encoded unless encryption at rest and external secret practices are configured.

### PV/PVC/StorageClass?

StorageClass defines dynamic provisioning. PVC is the request for storage. PV is the actual volume resource. In EKS, EBS CSI commonly provisions EBS-backed PVs.

### DaemonSet use cases?

Log agents, metrics agents, CNI plugin, CSI node plugin, security agents. One Pod per node or per selected node.

## Probes

### Liveness?

"Should kubelet restart this container?"

### Readiness?

"Should this Pod receive traffic?"

### Startup?

"Give slow-starting apps time before liveness begins."

Interview warning:

Bad liveness probes can create restart loops. Bad readiness probes can remove healthy Pods from traffic.

## Networking

### ALB 503. What do you check?

```bash
kubectl get ingress -n <ns>
kubectl describe ingress <name> -n <ns>
kubectl get svc,endpoints,endpointslice -n <ns>
kubectl get targetgroupbinding -n <ns>
kubectl describe pod <pod> -n <ns>
```

Likely causes:

- no healthy targets
- readiness failing
- Service selector mismatch
- targetPort mismatch
- security group issue

### NetworkPolicy does not work. Why?

The CNI may not enforce it. Pod labels may not match. Policy may allow more than expected. DNS/egress rules may be missing. Policies are additive.

### SG vs NACL?

Security Group is stateful and attached to ENIs. NACL is stateless and subnet-level.

## IAM And RBAC

### How does a developer get EKS access?

They authenticate with AWS IAM or federated role. EKS maps that IAM principal to Kubernetes username/groups using Access Entries or legacy `aws-auth`. Kubernetes RBAC then authorizes actions.

### IAM vs RBAC?

IAM controls AWS API permissions. Kubernetes RBAC controls Kubernetes API permissions.

### Human access vs IRSA?

Human access maps IAM principal to Kubernetes permissions. IRSA maps Kubernetes ServiceAccount to IAM role for Pods calling AWS APIs.

## Helm

### Why Helm?

Helm packages Kubernetes manifests into a reusable chart with configurable values and release history.

### `helm lint`?

Checks chart structure and template syntax before deployment.

### `helm template`?

Renders final YAML locally so you can see what will be applied.

### `helm upgrade --install`?

Installs if release does not exist, otherwise upgrades existing release.

### Rollback without Argo CD?

Use Helm release history:

```bash
helm history <release> -n <namespace>
helm rollback <release> <revision> -n <namespace>
```

## GitHub Actions And CI/CD

### Why OIDC?

GitHub gets a short-lived token and assumes an AWS IAM role. No long-lived AWS access keys are stored in GitHub.

### Production pipeline?

```text
PR opened
-> lint
-> unit tests
-> SAST/dependency scan
-> build image
-> image scan
-> preview/dev deploy
-> approval
-> staging deploy
-> smoke tests
-> production deploy
-> canary/rolling rollout
-> metrics check
-> rollback if needed
```

### One branch or many?

Many companies protect `main`, use PRs, feature branches, environment branches or tags, and environment approvals. Deployment triggers may differ by branch, tag, or manual promotion.

## Autoscaling

### HPA vs VPA vs Cluster Autoscaler/Karpenter?

HPA scales Pods. VPA recommends or changes resource requests. Cluster Autoscaler/Karpenter scales nodes.

### HPA not scaling?

Metrics missing, CPU requests missing, target threshold not reached, maxReplicas too low, or app bottleneck is not CPU/memory.

## Storage

### Why EBS volume caused scheduling issue?

EBS is AZ-scoped. Pod using that volume must run in the same AZ as the volume.

### ReclaimPolicy?

Controls what happens to the PV after PVC deletion. `Delete` removes backing storage; `Retain` preserves it and may leave cost behind.

## Observability

### How do you monitor EKS?

Use CloudWatch/Container Insights for AWS and cluster metrics, Prometheus for Kubernetes/app metrics, Grafana dashboards, logs through CloudWatch or Fluent Bit, traces through OpenTelemetry/X-Ray, and alerts on SLIs like error rate and latency.

### Golden signals?

Latency, traffic, errors, saturation.

### During incident?

Mitigate first, then root cause. Check recent deployments, logs, metrics, events, traces, ALB target health, Kubernetes object state, and AWS audit trails.

## Cost

### How reduce EKS cost?

Rightsize requests, improve bin packing, use HPA and node autoscaling, consider Spot, reduce NAT/cross-AZ traffic, clean EBS/ALB/ECR/Secrets/Route53 leftovers, control log retention and metric cardinality, use budgets and anomaly detection.

## Cluster Upgrade

### How upgrade EKS safely?

Check deprecated APIs, upgrade control plane, upgrade add-ons, upgrade node groups, drain nodes safely respecting PDBs, verify workloads, monitor metrics, and keep rollback/restore plan.

## Troubleshooting Rapid Fire

### CrashLoopBackOff

Check previous logs, pod events, env vars, command/args, app port, missing config/secret, filesystem permissions.

```bash
kubectl logs <pod> -n <ns> --previous
kubectl describe pod <pod> -n <ns>
```

### Pending

Check scheduling events, resource requests, taints, affinity, quota, PVC, AZ constraints.

### ErrImagePull/ImagePullBackOff

Check image name/tag, registry, ECR permissions, architecture, and node network path.

### Readiness failing

Check app dependency, endpoint path, service targetPort, logs, Redis/DB connectivity.

### ALB no DNS

Check AWS Load Balancer Controller, IngressClass, subnet tags, IAM permissions, certificate ARN.

### AccessDenied from AWS SDK inside Pod

Check IRSA service account annotation, pod serviceAccountName, OIDC provider, trust policy `sub`, and IAM policy action/resource.

## Questions To Ask Interviewer

Ask these when they invite questions:

- "How do you manage EKS access today: Access Entries, aws-auth, or GitOps-managed RBAC?"
- "Do teams deploy through Helm directly, Argo CD, or another CD tool?"
- "How do you handle cluster upgrades and node upgrades?"
- "What is your observability stack: CloudWatch, Prometheus, Grafana, OpenTelemetry?"
- "Do you use Cluster Autoscaler or Karpenter?"
- "How do you separate dev, staging, and production access?"
- "What are the biggest reliability problems the platform team is solving right now?"

These questions make you sound like someone thinking about real operations.

## Final Confidence Script

Before the interview, read this out loud:

```text
I know the traffic path from DNS to ALB to Ingress to Service to Pod.
I know the identity path from GitHub OIDC and IRSA to AWS IAM.
I know storage through StorageClass, PVC, PV, EBS CSI, and StatefulSet.
I know deployment through Docker, ECR, Helm, and rollback.
I know operations through probes, HPA, NetworkPolicy, PDB, logs, metrics, and troubleshooting.
When I do not know the answer instantly, I can debug layer by layer.
```

That is the mindset.
