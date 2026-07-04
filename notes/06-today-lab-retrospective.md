# EKS Interview Lab Retrospective

This note captures what we actually built, broke, diagnosed, fixed, and learned. Treat this as your "story bank" for interviews.

## What We Built

We built a small but realistic EKS application platform:

- EKS cluster named `interview-eks` in `us-east-1`
- self-managed Spot node group with two worker nodes
- Dockerized FastAPI application
- ECR repository for container images
- Helm chart for Kubernetes deployment
- GitHub Actions pipeline using OIDC to assume an AWS IAM role
- ALB Ingress through AWS Load Balancer Controller
- Route 53 alias record for `app.tanscape.online`
- ACM certificate for HTTPS
- Redis StatefulSet with EBS-backed PVC
- StorageClass using EBS CSI and `gp3`
- IRSA for pod-to-AWS permissions
- AWS Secrets Manager integration
- ConfigMap and Kubernetes Secret
- HPA, PDB, DaemonSet, ResourceQuota, LimitRange, NetworkPolicy
- Canary traffic split through ALB weighted target groups

The value of this lab is not that it is production-ready. The value is that it touches the major concepts interviewers expect you to understand.

## Important Incidents We Practiced

### 1. CrashLoopBackOff From Bad Command Override

We manually patched the app Deployment with:

```bash
kubectl patch deployment interview-app -n interview --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["python","-c","import sys; sys.exit(1)"]}]'
```

What happened:

- the container started
- Python immediately exited with status code `1`
- kubelet restarted it repeatedly
- pod entered `CrashLoopBackOff`
- startup probe failed because nothing was listening on port `8080`
- `kubectl logs --previous` showed no useful output because the process exited before logging

Key concept:

`CrashLoopBackOff` means Kubernetes can start the container, but the process keeps exiting. It is different from `ImagePullBackOff`, where the image cannot even be pulled.

How we fixed it:

```bash
kubectl patch deployment interview-app -n interview --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/command"}]'

kubectl rollout status deployment/interview-app -n interview --timeout=180s
```

Interview line:

"I check `kubectl describe pod` first for events and probe failures, then `kubectl logs --previous` if the container restarted. If a manual patch caused drift, I remove the bad field or redeploy from the desired source."

### 2. Helm Did Not Automatically Remove Drift

After the bad command patch, a normal Helm upgrade did not remove the `command` field immediately because that field had been manually added to the live object and the chart did not explicitly manage it.

Key concept:

Helm is not a continuous reconciler like Argo CD. Helm applies a release, but manual live edits can create drift. Depending on the patch and field ownership, drift may survive longer than expected.

Interview line:

"Manual cluster changes can diverge from Git and Helm. In production I prefer GitOps or strong change controls, and I use `helm diff`, `kubectl diff`, or Argo CD drift detection."

### 3. ImagePullBackOff From Bad Image Tag

We intentionally deployed a non-existing image tag.

Expected symptoms:

- pod status: `ErrImagePull` then `ImagePullBackOff`
- events show image not found or authorization failure
- old pods may continue serving if rolling update strategy protects availability

Key concept:

Image failures are usually visible in pod events, not app logs, because the container never starts.

Interview line:

"For `ImagePullBackOff`, I inspect image name, tag, registry auth, ECR permissions, node networking, and pod events."

### 4. Helm Rollback

We rolled back with:

```bash
helm history interview-app -n interview
helm rollback interview-app 13 -n interview --wait --timeout 5m
```

Key concept:

Helm stores release revisions. A rollback creates a new revision using a previous manifest set. It is not the same as Git revert, but it is very useful during incidents.

Interview line:

"In a Helm-only CD setup, I can use `helm history` and `helm rollback`. In GitOps, rollback is usually done by reverting Git or syncing to a previous desired state."

### 5. HPA Scaling

We used load generation to make HPA scale the app.

Key concept:

CPU HPA uses actual CPU usage divided by requested CPU. If the app requests `100m` and uses `60m`, the utilization is `60%`.

Common reasons HPA does not scale:

- metrics-server is broken
- pod has no CPU request
- load is not CPU-bound
- HPA target is too high
- scale-up/down stabilization windows delay action

Interview line:

"HPA depends heavily on correct resource requests. Bad requests create bad autoscaling behavior."

### 6. NetworkPolicy Testing

We tested allowed and blocked traffic from the same namespace and a different namespace.

Key concept:

NetworkPolicy controls pod traffic, but only if the CNI supports enforcement. In our EKS lab, we enabled VPC CNI NetworkPolicy support.

Important distinction:

- Security Groups protect ENIs and AWS-level traffic
- NetworkPolicy protects Kubernetes pod communication intent
- IAM controls AWS API authorization

Interview line:

"NetworkPolicy is namespace and pod-selector driven. A Service may exist and DNS may resolve, but traffic can still be blocked by policy."

### 7. PDB And Node Drain

We practiced `kubectl drain`.

Key concepts:

- `cordon` prevents new scheduling on a node
- `drain` cordons and evicts pods
- PDB protects against voluntary disruptions
- PDB does not protect from sudden node crash
- DaemonSet pods are ignored during normal drain when using `--ignore-daemonsets`

Interview line:

"PDB helps during planned maintenance, node upgrades, and drain operations. It does not keep an app highly available by itself."

### 8. Redis StatefulSet And EBS Persistence

We deleted the Redis pod, and the counter continued from the previous value.

What this proved:

- pod identity stayed `interview-app-redis-0`
- PVC stayed bound
- EBS volume persisted
- recreated pod reused the existing volume

Interview line:

"The pod is replaceable; the persistent volume is the important state boundary."

### 9. EBS Zonal Scheduling Problem

After node drain and rescheduling, Redis became pending.

Root cause:

- Redis PVC was backed by an EBS volume in `us-east-1d`
- EBS volumes are zonal
- Redis pod had to run on a node in `us-east-1d`
- the only valid node had hit max pod density
- scheduler could not place Redis
- app readiness failed because Redis was unavailable

Commands that revealed the issue:

```bash
kubectl describe pod interview-app-redis-0 -n interview
kubectl get nodes -L topology.kubernetes.io/zone
kubectl describe pv <pv-name>
```

Useful event messages:

- `didn't match PersistentVolume's node affinity`
- `Too many pods`
- `node(s) were unschedulable`

Interview line:

"On EKS, EBS is zonal. If a pod uses an EBS-backed PV, it must land on a node in the same AZ. Pending pods may be caused by volume node affinity, not just CPU or memory."

### 10. Dashboard Vanished After Rollback

After Helm rollback, the app showed JSON instead of the polished dashboard.

Root cause:

- rollback moved the app back to an older image tag
- the older image did not contain the dashboard code
- the cluster was healthy, but the deployed app version changed

How we fixed it:

- updated dashboard code in `app/src/main.py`
- built a new `linux/amd64` image
- pushed to ECR
- deployed with Helm
- committed and pushed source
- GitHub Actions then deployed the commit SHA image

Interview line:

"A rollback can restore service but also revert features. Always verify the actual image tag and application behavior, not just pod readiness."

## Production Lessons From The Day

### Running Is Not Ready

A pod can be `Running` but `0/1 Ready`. The process exists, but readiness probe says it should not receive traffic.

### Logs Are Not Always Enough

For scheduling, image pull, volume attach, and admission failures, logs may not exist. Events are often more useful.

### Old Pods Can Save You

Our rolling update used:

```yaml
maxUnavailable: 0
maxSurge: 1
```

This allowed old healthy pods to keep serving while bad new pods failed.

### Small Nodes Have Pod Density Limits

We hit a real issue where a `t3.small` node had pod slots exhausted. CPU and memory looked okay, but the node could not accept more pods.

### Helm And GitHub Actions Can Both Deploy

We did a manual Helm deployment to restore quickly, then pushed source so GitHub Actions could converge the cluster to Git-backed state.

In a company, this should be controlled carefully. Manual deploys should be emergency-only or explicitly documented.

## How To Tell This Story In Interview

"I built a compact EKS lab with a Helm-deployed FastAPI app, ALB Ingress, Route 53, ACM, Redis StatefulSet on EBS, IRSA, Secrets Manager, HPA, NetworkPolicy, PDB, DaemonSet, ResourceQuota, and GitHub Actions OIDC. I practiced real failure modes: CrashLoopBackOff, ImagePullBackOff, Helm rollback, Redis dependency outage, HPA scale-up, NetworkPolicy blocking, node drain, and an EBS zonal scheduling issue caused by pod density. The strongest learning was that troubleshooting must follow the lifecycle: admission, scheduling, image pull, container start, probes, service endpoints, ingress, and cloud dependencies."

