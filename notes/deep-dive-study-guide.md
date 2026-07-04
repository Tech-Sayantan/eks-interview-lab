# EKS Interview Lab Deep Dive

This guide explains the exact lab we built, why each Kubernetes/AWS object exists, and how to talk about it in an interview.

## 1. Mental Model

Traffic path:

```text
Browser
  -> Route 53 DNS: app.tanscape.online
  -> AWS ALB created by AWS Load Balancer Controller
  -> Kubernetes Ingress
  -> Kubernetes Service interview-app
  -> Deployment pods
  -> Redis StatefulSet through headless Service
```

AWS identity path from the app:

```text
Pod
  -> Kubernetes ServiceAccount interview-app
  -> projected OIDC token
  -> AWS STS AssumeRoleWithWebIdentity
  -> IAM role interview-eks-interview-app-irsa
  -> AWS APIs allowed by that role
```

CI/CD path:

```text
GitHub Actions
  -> GitHub OIDC token
  -> AWS IAM role interview-eks-github-actions-deployer
  -> ECR push
  -> EKS kubeconfig
  -> Helm upgrade --install
```

Good interview summary:

> This lab deploys a Dockerized FastAPI app to EKS using Helm. The app is exposed through ALB Ingress, uses Redis through a StatefulSet and EBS-backed PVC, uses IRSA for AWS access, has probes, HPA, ResourceQuota, LimitRange, PDB, DaemonSet, NetworkPolicy, and a GitHub Actions OIDC pipeline.

## 2. Docker Layer

File: `app/Dockerfile`

What it does:

- Uses `python:3.12-slim`.
- Sets a working directory at `/app`.
- Creates a non-root Linux user called `app`.
- Installs dependencies from `requirements.txt`.
- Copies the source code.
- Runs as non-root.
- Starts Uvicorn on port `8080`.

Important interview points:

- Image is the immutable artifact.
- Container is a running instance of the image.
- In production, prefer small base images, pinned dependencies, non-root user, vulnerability scans, and multi-stage builds when useful.
- In Kubernetes, the image must be reachable by the node runtime. In our case, the image is stored in ECR.

Common failure:

- `ImagePullBackOff`: wrong tag, wrong ECR repo, missing IAM/ECR permission, private registry auth issue, or architecture mismatch.

## 3. Application Layer

File: `app/src/main.py`

Endpoints:

- `/healthz`: simple process health. Used by liveness/startup probes.
- `/readyz`: checks Redis. If Redis is unavailable, readiness fails.
- `/config`: shows ConfigMap-derived values.
- `/secret-check`: proves Secret is present without printing the secret.
- `/redis/incr`: proves app-to-Redis connectivity and persistence path.
- `/aws/identity`: proves IRSA by returning the IAM role identity from STS.
- `/burn`: burns CPU so HPA can be tested.

Important interview point:

> Liveness means "should Kubernetes restart me?" Readiness means "should I receive traffic?" In this lab readiness depends on Redis, so if Redis is broken, the app process may still be alive but should not receive traffic.

## 4. Helm Mental Model

Folder: `charts/interview-app/`

Helm chart parts:

- `Chart.yaml`: chart metadata.
- `values.yaml`: default configurable values.
- `templates/*.yaml`: Kubernetes manifests with Go templating.
- `_helpers.tpl`: reusable naming/label helper templates.

Useful commands:

```bash
helm lint charts/interview-app -f manual-values/my-values.yaml
helm template interview-app charts/interview-app -n interview -f manual-values/my-values.yaml
helm upgrade --install interview-app charts/interview-app -n interview -f manual-values/my-values.yaml --wait --timeout 10m
helm status interview-app -n interview
helm history interview-app -n interview
helm rollback interview-app <revision> -n interview
```

What `helm lint` does:

- Checks chart structure.
- Checks template syntax.
- Catches many obvious chart mistakes before touching the cluster.
- It does not guarantee the cluster will accept everything because cluster-side RBAC, CRDs, webhooks, quotas, and API permissions are checked only when applying.

What `helm template` does:

- Renders final Kubernetes YAML locally.
- Great for debugging what Helm will actually send to Kubernetes.

What `helm upgrade --install` does:

- If release does not exist, install it.
- If release exists, upgrade it.
- This is why it is common in CI/CD.

What `--wait` means:

- Helm waits until resources become ready.
- In our lab, Helm failed when Deployment readiness and Redis StatefulSet were unhealthy. That failure was useful because it exposed a real storage/security-context issue.

## 5. `values.yaml`

File: `charts/interview-app/values.yaml`

Think of this as the environment control panel.

Important sections:

- `replicaCount`: desired app pod count.
- `image`: repository/tag/pull policy.
- `serviceAccount`: name and IRSA annotation.
- `config`: non-secret app config.
- `secret`: demo Secret value.
- `service`: ClusterIP service config.
- `ingress`: ALB Ingress host, certificate, annotations.
- `resources`: CPU/memory requests and limits.
- `autoscaling`: HPA settings.
- `networkPolicy`: traffic policy toggles.
- `storageClass`: EBS CSI dynamic volume settings.
- `redis`: Redis StatefulSet settings.
- `daemonset`: node-reporter settings.
- `resourceQuota` and `limitRange`: namespace guardrails.
- `vpa`: optional, disabled unless VPA CRDs exist.

Interview line:

> Helm lets us keep one reusable chart and inject environment-specific values for dev, staging, prod, or a manual lab deployment.

## 6. Deployment

File: `charts/interview-app/templates/deployment.yaml`

What it creates:

- `Deployment` for the FastAPI web app.
- Uses `replicaCount: 2`.
- Runs app container on port `8080`.
- Reads config from ConfigMap.
- Reads demo secret from Secret.
- Injects pod metadata using the Downward API.
- Uses liveness, readiness, and startup probes.
- Sets resource requests and limits.
- Uses a restricted container security context.

Important fields:

- `selector.matchLabels`: how Deployment finds its pods.
- `template.metadata.labels`: labels placed on pods.
- `serviceAccountName`: connects pods to the IRSA-enabled ServiceAccount.
- `resources.requests`: needed for scheduling and HPA.
- `resources.limits`: prevents one pod from consuming unlimited CPU/memory.

Production issues:

- Bad image tag -> `ImagePullBackOff`.
- App starts then exits -> `CrashLoopBackOff`.
- Readiness path fails -> pod is running but not in Service endpoints.
- Requests too high -> pod Pending due to insufficient capacity.
- Requests too low -> noisy neighbor risk and bad HPA decisions.

## 7. Service

File: `charts/interview-app/templates/service.yaml`

What it creates:

- A `ClusterIP` Service named `interview-app`.
- Exposes port `80`.
- Forwards to the pod's named port `http`, which is container port `8080`.
- Selects web pods by labels.

Important interview point:

> Pods are ephemeral; Service gives a stable virtual IP and DNS name for a changing set of pods.

Common issue:

- Service selector does not match pod labels. Then the Service has no endpoints and ALB may return 503.

## 8. Ingress And ALB

File: `charts/interview-app/templates/ingress.yaml`

What it creates:

- Kubernetes `Ingress`.
- `ingressClassName: alb`.
- AWS Load Balancer Controller watches it and creates an AWS ALB.
- TLS certificate comes from ACM.
- Host rule maps `app.tanscape.online` to the Kubernetes Service.

Important annotations:

- `alb.ingress.kubernetes.io/scheme: internet-facing`: public ALB.
- `alb.ingress.kubernetes.io/target-type: ip`: targets pod IPs directly.
- `alb.ingress.kubernetes.io/healthcheck-path: /healthz`: ALB target health path.
- `alb.ingress.kubernetes.io/certificate-arn`: ACM certificate.
- `alb.ingress.kubernetes.io/ssl-redirect: "443"`: HTTP redirects to HTTPS.

Ingress interview line:

> Ingress is only an intent object. It needs an Ingress Controller. In AWS, AWS Load Balancer Controller translates the Kubernetes Ingress into ALB, listeners, rules, target groups, security group rules, and TargetGroupBindings.

Common production issues:

- Ingress has no address: controller problem, IAM issue, subnet tags, wrong class.
- ALB returns 503: no healthy targets, readiness failure, bad service selector, wrong target port.
- TLS broken: cert in wrong region, wrong hostname, DNS validation not complete.

## 9. ConfigMap

File: `charts/interview-app/templates/configmap.yaml`

What it creates:

- Non-secret configuration:
  - `APP_ENV`
  - `APP_MESSAGE`
  - `REDIS_HOST`
  - `REDIS_PORT`

Important interview point:

> ConfigMap decouples config from image. Same image can run in multiple environments with different config.

Caveat:

- Environment variables from ConfigMap do not automatically update inside an already-running process. Usually you need pod restart/rollout.

## 10. Secret

File: `charts/interview-app/templates/secret.yaml`

What it creates:

- Opaque Kubernetes Secret with `DEMO_API_KEY`.

Important interview point:

> Kubernetes Secrets are base64-encoded objects, not magically secure by themselves. In production, enable encryption at rest and consider AWS Secrets Manager/External Secrets for real sensitive values.

## 11. ServiceAccount And IRSA

File: `charts/interview-app/templates/serviceaccount.yaml`

What it creates:

- Kubernetes `ServiceAccount`.
- In our real values, it has annotation:

```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::923988301700:role/interview-eks-interview-app-irsa
```

How IRSA works:

1. EKS cluster has an OIDC issuer.
2. IAM role trusts that OIDC issuer.
3. IAM trust policy allows one Kubernetes service account identity.
4. Pod gets projected service account token.
5. AWS SDK uses token to call STS `AssumeRoleWithWebIdentity`.
6. Pod receives temporary credentials for that role.

Interview line:

> IRSA avoids storing AWS keys in pods and avoids giving all workloads the broad node IAM role.

Common issue:

- Trust policy `sub` must match:

```text
system:serviceaccount:interview:interview-app
```

## 12. Redis Headless Service And StatefulSet

File: `charts/interview-app/templates/redis-statefulset.yaml`

What it creates:

- A headless Service `interview-app-redis`.
- A StatefulSet `interview-app-redis`.
- One Redis pod.
- One PVC through `volumeClaimTemplates`.

Headless Service:

- `clusterIP: None`.
- Provides stable DNS records for StatefulSet pods.
- Useful when clients need stable network identity.

StatefulSet:

- Stable pod name: `interview-app-redis-0`.
- Stable PVC: `data-interview-app-redis-0`.
- Ordered creation/deletion behavior.
- Good for stateful systems where identity/storage matter.

PVC flow:

```text
StatefulSet volumeClaimTemplates
  -> PVC data-interview-app-redis-0
  -> StorageClass interview-gp3
  -> EBS CSI driver
  -> AWS EBS volume
  -> PV bound to PVC
  -> mounted into Redis pod at /data
```

Real issue we faced:

- Redis initially failed because it could not write/chown the EBS-mounted `/data`.
- The PVC and EBS volume were fine.
- The issue was container filesystem/security context behavior.

Interview line:

> When PVC is Bound but app still crashes, I check container logs and mount permissions. Storage provisioning and application write permissions are different layers.

## 13. StorageClass

File: `charts/interview-app/templates/storageclass.yaml`

What it creates:

- `StorageClass` named `interview-gp3`.
- Provisioner: `ebs.csi.aws.com`.
- Type: `gp3`.
- Encrypted EBS volumes.
- `reclaimPolicy: Delete`.
- `volumeBindingMode: WaitForFirstConsumer`.

Important interview points:

- StorageClass defines how volumes are dynamically provisioned.
- PVC requests storage.
- PV represents the actual provisioned volume.
- EBS is AZ-scoped and usually `ReadWriteOnce`.
- `WaitForFirstConsumer` delays volume creation until Kubernetes knows where the pod will run. This avoids creating an EBS volume in the wrong AZ.

Real CI/CD issue we faced:

- GitHub role could deploy namespace objects, but failed on StorageClass.
- Reason: StorageClass is cluster-scoped.
- Lesson: namespace-level access is not enough for cluster-scoped Kubernetes resources.

## 14. HPA

File: `charts/interview-app/templates/hpa.yaml`

What it creates:

- `HorizontalPodAutoscaler`.
- Targets the Deployment.
- Min replicas: 2.
- Max replicas: 5.
- CPU target: 60 percent average utilization.

Requirements:

- metrics-server must be running.
- Pods must have CPU requests.

Interview line:

> HPA compares observed CPU usage against requested CPU. If requests are missing or metrics-server is broken, HPA cannot make good decisions.

Test command:

```bash
kubectl run load -n interview --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://interview-app.interview.svc.cluster.local/burn?seconds=3; done'
kubectl get hpa -n interview -w
```

Clean up:

```bash
kubectl delete pod load -n interview --ignore-not-found=true
```

## 15. NetworkPolicy

File: `charts/interview-app/templates/networkpolicy.yaml`

What it creates:

- Policy for app pods.
- Policy for Redis pods.

App pods are allowed:

- Ingress to app port `8080`.
- Egress to DNS in `kube-system` on port `53`.
- Egress to Redis on port `6379`.
- Egress to HTTPS on port `443` for AWS SDK/STS calls.

Redis pods are allowed:

- Ingress only from app pods on port `6379`.

Important interview points:

- NetworkPolicy is namespace-scoped.
- It selects pods using labels.
- It is additive.
- Once a pod is selected for ingress or egress policy, only allowed traffic passes for that direction.
- A NetworkPolicy object is only useful if the CNI enforces it.

EKS-specific point:

> On EKS with Amazon VPC CNI, NetworkPolicy enforcement must be enabled. Applying NetworkPolicy YAML alone is not enough if the CNI does not enforce it.

## 16. DaemonSet

File: `charts/interview-app/templates/daemonset.yaml`

What it creates:

- One `node-reporter` pod per node.
- It logs node/pod/namespace info every 60 seconds.

Real-world use cases:

- Log agents.
- Metrics agents.
- Security agents.
- CNI node agents.
- CSI node plugins.

Interview line:

> Deployment scales by replica count; DaemonSet scales by node count.

## 17. ResourceQuota And LimitRange

Files:

- `charts/interview-app/templates/resourcequota.yaml`
- `charts/interview-app/templates/limitrange.yaml`

ResourceQuota:

- Caps total namespace resource usage.
- Example: max pods, max CPU requests, max memory requests, max PVC count.

LimitRange:

- Applies default requests/limits to containers if not specified.
- Can enforce min/max per container.

Interview line:

> ResourceQuota protects the namespace as a whole. LimitRange protects individual objects and provides defaults.

Common issue:

- A pod may fail admission if quota requires CPU/memory requests and the pod does not specify them.

## 18. PDB

File: `charts/interview-app/templates/pdb.yaml`

What it creates:

- `PodDisruptionBudget`.
- Requires at least one app pod available during voluntary disruptions.

Voluntary disruptions:

- Node drain.
- Cluster/node maintenance.
- Autoscaler removing a node.

Important caveat:

- PDB does not protect against involuntary failures like node crash or kernel panic.

## 19. VPA

File: `charts/interview-app/templates/vpa.yaml`

Why it is disabled:

- VPA requires VPA CRDs/controller to be installed.
- Without CRDs, applying a VPA object fails.

Concept:

- HPA changes number of pods.
- VPA changes pod resource requests.
- Cluster Autoscaler changes number of nodes.

Interview line:

> HPA, VPA, and Cluster Autoscaler operate at different layers. HPA scales replicas, VPA tunes requests, and Cluster Autoscaler scales node capacity.

## 20. GitHub Actions Workflow

File: `.github/workflows/build-deploy.yml`

Important parts:

- `permissions: id-token: write` allows GitHub to request an OIDC token.
- `aws-actions/configure-aws-credentials` exchanges GitHub OIDC token for AWS role credentials.
- `amazon-ecr-login` logs Docker into ECR.
- Docker builds and pushes an image tagged by commit SHA.
- `aws eks update-kubeconfig` configures Kubernetes access.
- Helm renders and applies the chart.

Why we use GitHub variables:

- Non-sensitive values like region, cluster, namespace, and host are repo variables.
- No long-lived AWS access keys are stored in GitHub.

Real issues we faced:

- OIDC trust policy mismatch caused `AssumeRoleWithWebIdentity` failure.
- Kubernetes access policy was initially too narrow for `StorageClass`.

Interview line:

> GitHub Actions OIDC removes long-lived cloud credentials from CI. The hard parts are IAM trust policy conditions and giving the role the right Kubernetes access scope.

## 21. Good Troubleshooting Order

Use this order when something breaks:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
```

For app exposure:

```bash
kubectl get ingress -n interview
kubectl describe ingress interview-app -n interview
kubectl get svc,endpoints -n interview
kubectl describe targetgroupbinding -n interview
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

For storage:

```bash
kubectl get storageclass,pv,pvc -A
kubectl describe pvc data-interview-app-redis-0 -n interview
kubectl logs -n kube-system deployment/ebs-csi-controller
```

For autoscaling:

```bash
kubectl top pods -n interview
kubectl describe hpa interview-app -n interview
```

For IRSA:

```bash
kubectl get sa interview-app -n interview -o yaml
kubectl exec -n interview deploy/interview-app -- env | grep AWS
curl -s https://app.tanscape.online/aws/identity
```

## 22. Tomorrow's Drill Plan

Keep the cluster one more day only if you actively use it. These are high-value drills.

### Drill 1: Read The Live State

```bash
kubectl get all -n interview
kubectl get ingress,pvc,hpa,networkpolicy -n interview
kubectl get storageclass,pv
```

Goal:

- Explain every line without panic.

### Drill 2: Force A Readiness Failure

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=0
kubectl get pods -n interview
kubectl describe deploy interview-app -n interview
curl -i https://app.tanscape.online/readyz
```

Recover:

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=1
kubectl rollout status statefulset/interview-app-redis -n interview
kubectl rollout restart deployment/interview-app -n interview
```

What to learn:

- App can be alive but not ready.
- Service endpoints depend on readiness.

### Drill 3: Force CrashLoopBackOff

Patch the Deployment so the container exits immediately:

```bash
kubectl patch deployment interview-app -n interview --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["python","-c","import sys; sys.exit(1)"]}]'
kubectl get pods -n interview -w
kubectl logs -n interview deploy/interview-app --previous
```

Recover:

```bash
helm upgrade --install interview-app charts/interview-app -n interview -f manual-values/my-values.yaml --wait --timeout 10m
```

What to learn:

- CrashLoopBackOff means container starts and exits repeatedly.
- `logs --previous` is important because current container may have already restarted.

### Drill 4: Force ImagePullBackOff

```bash
kubectl set image deployment/interview-app app=bad-image-does-not-exist:bad -n interview
kubectl get pods -n interview -w
kubectl describe pod -n interview -l app.kubernetes.io/component=web
```

Recover:

```bash
helm upgrade --install interview-app charts/interview-app -n interview -f manual-values/my-values.yaml --wait --timeout 10m
```

What to learn:

- `describe pod` usually reveals pull/auth/tag errors.

### Drill 5: Test NetworkPolicy

Try Redis from an unrelated pod:

```bash
kubectl run net-test -n interview --rm -i --restart=Never --image=public.ecr.aws/docker/library/busybox:1.36 -- sh -c 'nc -vz -w 3 interview-app-redis 6379'
```

Expected:

- It should fail because Redis only allows traffic from app-labeled pods.

What to learn:

- NetworkPolicy depends on labels and is enforced by the CNI.

### Drill 6: Trigger HPA

```bash
kubectl run load -n interview --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://interview-app.interview.svc.cluster.local/burn?seconds=3; done'
kubectl get hpa -n interview -w
```

Recover:

```bash
kubectl delete pod load -n interview --ignore-not-found=true
```

What to learn:

- HPA is not instant.
- It needs metrics-server and CPU requests.
- Scale down is intentionally slower due to stabilization.

### Drill 7: Study Ingress Deeply

```bash
kubectl describe ingress interview-app -n interview
kubectl get targetgroupbinding -n interview
kubectl describe targetgroupbinding -n interview
aws elbv2 describe-load-balancers --region us-east-1 --profile eks-lab
```

What to learn:

- Ingress object is Kubernetes-side intent.
- TargetGroupBinding connects Kubernetes service/pods to AWS target groups.
- ALB health and Kubernetes readiness are related but not identical checks.

### Drill 8: Rolling Update And Rollback

Deploy a harmless message change:

```bash
helm upgrade --install interview-app charts/interview-app -n interview -f manual-values/my-values.yaml --set config.appMessage="rolling update practice" --wait --timeout 10m
kubectl rollout status deployment/interview-app -n interview
helm history interview-app -n interview
```

Rollback:

```bash
helm history interview-app -n interview
helm rollback interview-app <previous-good-revision> -n interview
```

What to learn:

- Deployment performs rolling updates through ReplicaSets.
- Helm keeps release history.
- Kubernetes rollout and Helm release history are related but not the same thing.

## 23. Production Problems To Be Ready For

Pod Pending:

- Not enough CPU/memory.
- PVC not bound.
- Taints/tolerations.
- Node selector/affinity.
- Quota exceeded.

CrashLoopBackOff:

- App crash.
- Missing env/config.
- Bad command.
- Permission issue.
- Dependency startup assumptions.

ImagePullBackOff:

- Wrong tag.
- Missing ECR auth.
- Repo not found.
- Wrong architecture.

ALB 503:

- No endpoints.
- Readiness failing.
- Target group unhealthy.
- Service selector mismatch.
- Wrong port.

PVC stuck:

- CSI driver missing/broken.
- IAM permission missing.
- Wrong StorageClass.
- AZ scheduling conflict.

HPA unknown:

- metrics-server not ready.
- Missing CPU requests.
- Metrics delay.

NetworkPolicy surprise:

- CNI not enforcing.
- Label mismatch.
- DNS egress blocked.
- Multiple policies are additive.

IRSA AccessDenied:

- ServiceAccount annotation missing.
- Wrong namespace/name in IAM trust.
- IAM policy lacks action.
- Pod not restarted after ServiceAccount change.

## 24. Teardown Reminder

Do this only after tomorrow's practice:

```bash
export AWS_PROFILE="eks-lab"
export AWS_REGION="us-east-1"
export CLUSTER_NAME="interview-eks"
export NAMESPACE="interview"
export HELM_RELEASE="interview-app"
export ECR_REPOSITORY="interview-app"
export IRSA_BUCKET_NAME="923988301700-us-east-1-interview-eks-irsa-demo"
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:923988301700:certificate/a6063a6f-0f64-4f83-8d68-279354e69da2"

helm uninstall interview-app -n interview --wait --timeout 5m
kubectl delete pvc --all -n interview --ignore-not-found=true
infra/scripts/09-destroy.sh
```

Then manually check AWS Console:

- EKS clusters.
- EC2 Load Balancers.
- EC2 Volumes.
- EC2 NAT Gateways.
- CloudFormation stacks.
- Route 53 records.
- ECR repository if you want to remove images.
- S3 bucket if you want to remove the IRSA demo bucket.
