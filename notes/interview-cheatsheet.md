# Interview Cheatsheet

## Docker

Explain:

- Image is immutable layers; container is a running instance of an image.
- Dockerfile should use a small base image, non-root user, `.dockerignore`, pinned dependencies, and health-friendly app behavior.
- `CMD` is default runtime command; `ENTRYPOINT` is the executable contract.
- In Kubernetes, the image must be reachable by the node runtime, usually from ECR in AWS.

Common issue:

- `ImagePullBackOff`: wrong image tag, private registry auth, ECR repo missing, wrong architecture, or node cannot reach registry.

## EKS

Explain:

- AWS manages the Kubernetes control plane.
- You manage worker capacity for self-managed node groups.
- Self-managed nodes do not appear as EKS managed node groups in the same way and upgrades are your responsibility.
- Control plane and kubelet versions should stay close; version skew matters.

Good interview line:

> EKS removes the operational burden of etcd and API server HA, but it does not remove responsibility for node upgrades, IAM boundaries, networking, storage, add-ons, and workload reliability.

## VPC, Subnets, SG, NACL

Explain:

- VPC is the network boundary.
- Subnets are AZ-scoped.
- Public subnet has route to Internet Gateway.
- Private subnet reaches internet through NAT Gateway or VPC endpoints.
- Security Groups are stateful and attached to ENIs.
- NACLs are stateless and applied at subnet level.
- ALB needs public subnets for internet-facing ingress.

Lab caveat:

- This lab uses public worker nodes to avoid NAT Gateway cost. Production usually uses private nodes.

## Deployment vs StatefulSet

Deployment:

- ReplicaSet-managed, interchangeable pods.
- Best for stateless workloads.
- Pod names are not stable.

StatefulSet:

- Stable pod identity.
- Ordered rollout.
- Stable PVC per replica.
- Often paired with a headless service.

## Service vs Ingress

Service:

- Stable virtual IP/DNS for a set of pods.
- Uses label selectors.
- Types: ClusterIP, NodePort, LoadBalancer.

Ingress:

- HTTP/HTTPS routing object.
- Needs a controller.
- In AWS, AWS Load Balancer Controller watches Ingress and creates ALB resources.

## Probes

Liveness probe:

- Tells kubelet when to restart a container.
- Use it for deadlock or unrecoverable process failure.
- Bad liveness probes can cause restart loops.

Readiness probe:

- Tells Kubernetes whether the pod should receive traffic.
- Failed readiness removes the pod from Service endpoints.
- Use it for dependencies like DB/cache availability or app startup.

Startup probe:

- Protects slow-starting apps from liveness killing them too early.
- Once startup succeeds, liveness/readiness take over.

This lab has:

- App startup: `/healthz`.
- App liveness: `/healthz`.
- App readiness: `/readyz`, which checks Redis.
- Redis TCP liveness/readiness on port `6379`.

## NetworkPolicy

Explain:

- NetworkPolicy is namespace-scoped.
- It selects pods with labels.
- Once a pod is selected by an ingress policy, only allowed ingress is accepted.
- Once a pod is selected by an egress policy, only allowed egress is accepted.
- Policies are additive: multiple policies combine allowed traffic.
- Kubernetes NetworkPolicy needs a CNI/plugin that enforces it.

EKS-specific line:

> On EKS, a NetworkPolicy object alone is not enough unless the CNI enforces it. Amazon VPC CNI can enforce Kubernetes NetworkPolicies when network policy support is enabled, and it uses an eBPF-based implementation.

This lab allows:

- ALB/external traffic to the app on `8080`.
- App to Redis on `6379`.
- App DNS to kube-system on `53`.
- App HTTPS egress on `443` for AWS STS/SDK calls.
- Redis ingress only from app pods.

## ConfigMap vs Secret

ConfigMap:

- Non-sensitive config.
- Can be env vars or mounted files.

Secret:

- Sensitive-ish data, base64 encoded by default, not automatically encrypted unless configured at rest.
- For production, prefer external secret managers or encrypted GitOps approaches.

## PV, PVC, StorageClass

StorageClass:

- Defines dynamic provisioning behavior.
- This lab uses EBS CSI with `ebs.csi.aws.com`.

PVC:

- User request for storage.

PV:

- Actual storage resource bound to a PVC.

Important EBS point:

- EBS is AZ-scoped and normally ReadWriteOnce. A pod using the volume must run in the same AZ as the volume.

## IRSA

Explain:

- Kubernetes service account is mapped to an IAM role through OIDC.
- Pod gets a projected service account token.
- AWS SDK exchanges that token through STS `AssumeRoleWithWebIdentity`.
- This avoids long-lived AWS keys and avoids giving every pod the node IAM role.

Common issue:

- IAM trust policy `sub` does not match `system:serviceaccount:<namespace>:<serviceaccount>`.

## HPA, VPA, Cluster Autoscaler

HPA:

- Changes pod replica count.
- Needs metrics and resource requests.

VPA:

- Recommends or changes pod CPU/memory requests.
- Can evict pods if update mode is not `Off`.

Cluster Autoscaler:

- Changes node count.
- HPA can create Pending pods, but Cluster Autoscaler is what adds nodes.

Good answer:

> HPA scales workload replicas; VPA tunes requests; Cluster Autoscaler scales infrastructure. They solve different layers of the capacity problem.

## ResourceQuota and LimitRange

ResourceQuota:

- Caps aggregate namespace usage.

LimitRange:

- Applies default requests/limits or min/max per object.

Common issue:

- Pods fail admission if no requests are set and quota requires requests.

## DaemonSet

Use cases:

- Log agent.
- Metrics agent.
- CNI plugin.
- CSI node plugin.
- Security agent.

## GitHub Actions OIDC

Explain:

- Workflow has `permissions: id-token: write`.
- GitHub issues short-lived OIDC token.
- AWS IAM role trust policy validates audience and subject.
- No AWS access keys are stored in GitHub.

Important:

- Restrict trust policy by repo and branch/environment.

## Helm

Explain:

- Chart = package.
- Values = environment-specific config.
- Template renders Kubernetes manifests.
- Release tracks installed revision.
- `helm upgrade --install` is idempotent.
- Rollback is possible with release history.

Commands:

```bash
helm lint charts/interview-app
helm template interview-app charts/interview-app -f .generated/deploy-values.yaml
helm history interview-app -n interview
helm rollback interview-app 1 -n interview
```
