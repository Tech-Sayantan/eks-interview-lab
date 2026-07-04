# 01 - Kubernetes Manifest Deep Dive

This chapter explains every Kubernetes object used in this lab, the exact chart file that creates it, what the rendered manifest looks like, why we need it for this app, and what interview questions may come from it.

Current rendered manifest:

```bash
helm template interview-app charts/interview-app \
  -n interview \
  -f manual-values/my-values.yaml \
  > .generated/rendered-current-manifests.yaml
```

The rendered file is useful because Helm templates are not what Kubernetes receives. Kubernetes receives the rendered YAML after `.Values`, `.Release`, helper templates, loops, and conditionals are resolved.

## Object Map

| Object | Template file | Why it exists |
|---|---|---|
| NetworkPolicy | `charts/interview-app/templates/networkpolicy.yaml` | Restrict app and Redis traffic |
| ResourceQuota | `charts/interview-app/templates/resourcequota.yaml` | Namespace-level guardrails |
| LimitRange | `charts/interview-app/templates/limitrange.yaml` | Default CPU/memory requests and limits |
| PodDisruptionBudget | `charts/interview-app/templates/pdb.yaml` | Keep at least one app pod available during voluntary disruption |
| ServiceAccount | `charts/interview-app/templates/serviceaccount.yaml` | Kubernetes identity for pods, used by IRSA |
| Secret | `charts/interview-app/templates/secret.yaml` | Demo sensitive value |
| ConfigMap | `charts/interview-app/templates/configmap.yaml` | Non-secret app config |
| StorageClass | `charts/interview-app/templates/storageclass.yaml` | Dynamic EBS provisioning |
| Headless Service | `charts/interview-app/templates/redis-statefulset.yaml` | Stable DNS for Redis StatefulSet |
| App Service | `charts/interview-app/templates/service.yaml` | Stable virtual IP/DNS for app pods |
| DaemonSet | `charts/interview-app/templates/daemonset.yaml` | One pod on each node |
| Deployment | `charts/interview-app/templates/deployment.yaml` | Stateless FastAPI app |
| HPA | `charts/interview-app/templates/hpa.yaml` | CPU-based pod autoscaling |
| StatefulSet | `charts/interview-app/templates/redis-statefulset.yaml` | Stateful Redis with stable PVC |
| Ingress | `charts/interview-app/templates/ingress.yaml` | HTTP/HTTPS entrypoint through AWS ALB |
| VPA | `charts/interview-app/templates/vpa.yaml` | Optional vertical autoscaling object, disabled in this lab |
| Practice PVC | `charts/interview-app/templates/practice-pvc.yaml` | Optional standalone PVC practice object, disabled in this lab |

## 1. Labels And Selectors

Before any single object, understand labels.

Rendered labels look like:

```yaml
labels:
  helm.sh/chart: interview-app-0.1.0
  app.kubernetes.io/name: interview-app
  app.kubernetes.io/instance: interview-app
  app.kubernetes.io/version: "1.0.0"
  app.kubernetes.io/managed-by: Helm
```

For web pods we also add:

```yaml
app.kubernetes.io/component: web
```

For Redis pods:

```yaml
app.kubernetes.io/component: redis
```

Why labels matter:

- Deployment uses selectors to manage pods.
- Service uses selectors to route traffic to pods.
- NetworkPolicy uses selectors to allow/deny traffic.
- HPA targets a Deployment.
- PDB selects pods to protect.
- `kubectl get pods -l ...` uses labels for filtering.

Interview line:

> In Kubernetes, labels are the glue. Controllers and Services do not usually track pods by name; they track them by label selectors.

Common failure:

If Service selector does not match pod labels, the Service has no endpoints. In AWS ALB, this often becomes a 503 because the target group has no healthy targets.

Check:

```bash
kubectl get pods -n interview --show-labels
kubectl get svc interview-app -n interview -o yaml
kubectl get endpoints interview-app -n interview
```

## 2. NetworkPolicy

Template file:

```text
charts/interview-app/templates/networkpolicy.yaml
```

Rendered app policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: interview-app-web
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: interview-app
      app.kubernetes.io/instance: interview-app
      app.kubernetes.io/component: web
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: interview-app
              app.kubernetes.io/instance: interview-app
              app.kubernetes.io/component: redis
      ports:
        - protocol: TCP
          port: 6379
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

Rendered Redis policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: interview-app-redis
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: interview-app
      app.kubernetes.io/instance: interview-app
      app.kubernetes.io/component: redis
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: interview-app
              app.kubernetes.io/instance: interview-app
              app.kubernetes.io/component: web
      ports:
        - protocol: TCP
          port: 6379
```

What it means:

- Web pods accept ingress on port `8080`.
- Web pods can use DNS on port `53`.
- Web pods can connect to Redis on `6379`.
- Web pods can reach HTTPS on `443`, needed for AWS SDK/STS calls.
- Redis pods accept traffic only from web pods.

Why the app needs it:

Without NetworkPolicy, any pod in the namespace could try to connect to Redis. In a real cluster, this is too open. NetworkPolicy gives pod-level segmentation.

Important nuance:

Kubernetes NetworkPolicy is enforced by the CNI plugin, not by the API server alone. On EKS with Amazon VPC CNI, we had to enable NetworkPolicy support. Applying YAML is not enough if the CNI is not enforcing it.

Interview questions:

- What happens when a pod is selected by an ingress NetworkPolicy?
- Are NetworkPolicies deny rules or allow rules?
- Are multiple NetworkPolicies additive?
- Does every CNI support NetworkPolicy?
- Why did we allow DNS egress?

Answers:

- Once selected for ingress, only allowed ingress traffic is accepted.
- NetworkPolicy is allow-list based. There is no explicit deny rule in standard Kubernetes NetworkPolicy.
- Policies are additive. If any policy allows traffic, traffic is allowed.
- No. The CNI must implement enforcement.
- DNS is required for service discovery and external calls. Without DNS egress, apps often fail in surprising ways.

Debug:

```bash
kubectl get networkpolicy -n interview
kubectl describe networkpolicy interview-app-web -n interview
kubectl describe networkpolicy interview-app-redis -n interview
kubectl get pods -n kube-system -l k8s-app=aws-node
```

Test Redis isolation:

```bash
kubectl run net-test -n interview --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/busybox:1.36 \
  -- sh -c 'nc -vz -w 3 interview-app-redis 6379'
```

Expected:

- It should fail from an unrelated pod because that pod does not have the web labels.

## 3. ResourceQuota

Template file:

```text
charts/interview-app/templates/resourcequota.yaml
```

Rendered:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: interview-app
spec:
  hard:
    limits.cpu: "4"
    limits.memory: 8Gi
    persistentvolumeclaims: "4"
    pods: "20"
    requests.cpu: "2"
    requests.memory: 4Gi
```

What it does:

- Caps total resource usage in the namespace.
- Prevents one app/team from using unlimited CPU, memory, pods, or PVCs.

Why our app needs it:

For practice, it teaches admission control and namespace guardrails. In production, platform teams use ResourceQuota to stop accidental runaway deployments.

Important distinction:

- ResourceQuota is aggregate namespace limit.
- LimitRange is per-container default/min/max policy.

Interview scenario:

Question: "A deployment is failing before pods are created. What do you check?"

Answer:

> I check events and admission errors. If a ResourceQuota exists, a pod may be rejected because it has no requests/limits or because namespace quota is exceeded.

Commands:

```bash
kubectl describe quota -n interview
kubectl get events -n interview --sort-by=.lastTimestamp
```

## 4. LimitRange

Template file:

```text
charts/interview-app/templates/limitrange.yaml
```

Rendered:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: interview-app
spec:
  limits:
    - type: Container
      default:
        cpu: 300m
        memory: 256Mi
      defaultRequest:
        cpu: 50m
        memory: 96Mi
```

What it does:

- If a container does not specify limits, Kubernetes can apply defaults.
- If a container does not specify requests, Kubernetes can apply default requests.

Why our app needs it:

Our app explicitly has resources, but LimitRange is included to learn namespace policy behavior.

Production value:

- Prevents "no requests/limits" workloads.
- Makes HPA and scheduling more predictable.

Interview line:

> LimitRange helps set sane defaults. ResourceQuota caps total namespace consumption. They are often used together.

## 5. PodDisruptionBudget

Template file:

```text
charts/interview-app/templates/pdb.yaml
```

Rendered:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: interview-app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: interview-app
      app.kubernetes.io/instance: interview-app
      app.kubernetes.io/component: web
```

What it does:

- During voluntary disruptions, Kubernetes tries to keep at least one matching pod available.

Voluntary disruptions:

- `kubectl drain`
- managed maintenance
- node scale-down
- cluster autoscaler removing nodes

Not protected:

- Node suddenly dies.
- Kernel panic.
- AZ outage.
- Pod OOMKilled.

Why our app needs it:

We run two replicas. PDB protects against both being voluntarily evicted at the same time.

Interview question:

"Why is PDB not the same as high availability?"

Answer:

> PDB only controls voluntary evictions. It does not create extra replicas and cannot prevent sudden failures. It should be combined with replicas, anti-affinity/spreading, readiness probes, and enough node capacity.

Check:

```bash
kubectl get pdb -n interview
kubectl describe pdb interview-app -n interview
```

## 6. ServiceAccount And IRSA

Template file:

```text
charts/interview-app/templates/serviceaccount.yaml
```

Rendered:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: interview-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::923988301700:role/interview-eks-interview-app-irsa
```

What it does:

- Gives Kubernetes identity to the app pods.
- On EKS, the annotation maps that ServiceAccount to an AWS IAM role.

Why our app needs it:

The `/aws/identity` endpoint calls AWS STS. We want the pod to use short-lived IAM role credentials, not static AWS keys.

IRSA flow:

```text
Pod starts with serviceAccountName: interview-app
-> EKS projects a service account token into pod
-> AWS SDK sees web identity environment variables
-> AWS SDK calls STS AssumeRoleWithWebIdentity
-> STS validates token against cluster OIDC provider and IAM trust policy
-> Pod receives temporary IAM credentials
```

Debug:

```bash
kubectl get sa interview-app -n interview -o yaml
kubectl exec -n interview deploy/interview-app -- env | grep AWS
curl -s https://app.tanscape.online/aws/identity
```

Common issue:

IAM trust policy must match:

```text
system:serviceaccount:interview:interview-app
```

Interview line:

> IRSA gives per-workload AWS permissions. It avoids long-lived access keys and avoids overusing the node instance role.

## 7. Secret

Template file:

```text
charts/interview-app/templates/secret.yaml
```

Rendered:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: interview-app
type: Opaque
stringData:
  DEMO_API_KEY: "demo-change-me"
```

What it does:

- Creates a Kubernetes Secret.
- `stringData` lets us write plaintext in YAML; Kubernetes stores it in the `data` field as base64.

Why our app needs it:

The app exposes `/secret-check`, which confirms the secret exists without printing it.

Important caveat:

Kubernetes Secret is not automatically "secure enough" just because it is called Secret.

Production considerations:

- Enable encryption at rest for Kubernetes secrets.
- Restrict RBAC access to secrets.
- Prefer AWS Secrets Manager or External Secrets Operator for real secret lifecycle.
- Never log secret values.

Interview line:

> Secrets are base64-encoded Kubernetes API objects. They need RBAC, encryption at rest, and careful operational handling.

## 8. ConfigMap

Template file:

```text
charts/interview-app/templates/configmap.yaml
```

Rendered:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: interview-app
data:
  APP_ENV: "eks"
  APP_MESSAGE: "deployed manually with Helm on EKS"
  REDIS_HOST: "interview-app-redis"
  REDIS_PORT: "6379"
```

What it does:

- Stores non-sensitive application configuration.

Why our app needs it:

The same Docker image can run locally, in EKS, or in CI deploys with different app messages and Redis host values.

How Deployment consumes it:

```yaml
env:
  - name: APP_ENV
    valueFrom:
      configMapKeyRef:
        name: interview-app
        key: APP_ENV
```

Important caveat:

If a ConfigMap is used as environment variables, changing the ConfigMap does not automatically update already-running processes. You usually restart/rollout pods.

Interview line:

> ConfigMap externalizes non-sensitive config from the container image.

## 9. StorageClass

Template file:

```text
charts/interview-app/templates/storageclass.yaml
```

Rendered:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: interview-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

What it does:

- Defines how Kubernetes dynamically creates persistent volumes.
- Uses AWS EBS CSI driver.
- Creates encrypted gp3 EBS volumes.

Key fields:

- `provisioner: ebs.csi.aws.com`: tells Kubernetes to use EBS CSI.
- `reclaimPolicy: Delete`: deleting PVC deletes the backing EBS volume.
- `allowVolumeExpansion: true`: PVC can be expanded later.
- `WaitForFirstConsumer`: wait until pod scheduling before creating the volume.

Why `WaitForFirstConsumer` matters:

EBS is AZ-scoped. If Kubernetes creates a volume in AZ A but schedules the pod in AZ B, the pod cannot attach the volume. Waiting lets scheduler pick a node/AZ first.

Real issue we faced:

GitHub Actions failed because the deployer role could not read/create cluster-scoped `StorageClass`. Namespace-scoped EKS access was not enough.

Interview line:

> PVC is a request, PV is the actual storage, and StorageClass defines the dynamic provisioning behavior.

## 10. Redis Headless Service

Template file:

```text
charts/interview-app/templates/redis-statefulset.yaml
```

Rendered:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: interview-app-redis
spec:
  clusterIP: None
  ports:
    - name: redis
      port: 6379
      targetPort: redis
  selector:
    app.kubernetes.io/name: interview-app
    app.kubernetes.io/instance: interview-app
    app.kubernetes.io/component: redis
```

What `clusterIP: None` means:

- This is a headless Service.
- Kubernetes does not allocate a virtual ClusterIP.
- DNS points more directly to matching pod endpoints.

Why our app needs it:

For Redis with StatefulSet, a headless Service gives stable DNS identity. With one Redis replica, the app can use `interview-app-redis`. With multiple replicas, pods would have stable names like:

```text
interview-app-redis-0.interview-app-redis.interview.svc.cluster.local
interview-app-redis-1.interview-app-redis.interview.svc.cluster.local
```

Interview line:

> StatefulSets are usually paired with headless Services to provide stable network identity.

## 11. App Service

Template file:

```text
charts/interview-app/templates/service.yaml
```

Rendered:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: interview-app
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: interview-app
    app.kubernetes.io/instance: interview-app
    app.kubernetes.io/component: web
```

What it does:

- Creates stable DNS and virtual IP for app pods.
- Routes Service port `80` to container named port `http`, which maps to `8080`.

Why our app needs it:

Ingress does not point directly to pods. It points to a Service. The Service finds ready pods through labels/endpoints.

Check:

```bash
kubectl get svc interview-app -n interview
kubectl get endpoints interview-app -n interview
```

Common issue:

If readiness fails, the pod may disappear from Service endpoints. Then the ALB may become unhealthy or return errors.

Interview line:

> Service decouples clients from pod lifecycle. Pods can die and be replaced, but the Service DNS remains stable.

## 12. DaemonSet

Template file:

```text
charts/interview-app/templates/daemonset.yaml
```

Rendered:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: interview-app-node-reporter
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: node-reporter
  template:
    metadata:
      labels:
        app.kubernetes.io/component: node-reporter
    spec:
      tolerations:
        - operator: Exists
      containers:
        - name: node-reporter
          image: "public.ecr.aws/docker/library/busybox:1.36"
          command:
            - sh
            - -c
            - |
              while true; do
                echo "node=$NODE_NAME pod=$POD_NAME namespace=$POD_NAMESPACE"
                sleep 60
              done
```

What it does:

- Runs one pod on every node.
- In our cluster with two nodes, it runs two node-reporter pods.

Why our app needs it:

The app itself does not need it. We included it because DaemonSet is an important interview topic and common in production.

Real use cases:

- Log collectors.
- Metrics agents.
- Security agents.
- CNI agents.
- CSI node plugins.

Interview line:

> Deployment scales by desired replica count. DaemonSet scales with node count.

## 13. Deployment

Template file:

```text
charts/interview-app/templates/deployment.yaml
```

Rendered core:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: interview-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: interview-app
      app.kubernetes.io/instance: interview-app
      app.kubernetes.io/component: web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: interview-app
        app.kubernetes.io/instance: interview-app
        app.kubernetes.io/component: web
    spec:
      serviceAccountName: interview-app
      containers:
        - name: app
          image: "923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1"
          ports:
            - name: http
              containerPort: 8080
```

What it does:

- Maintains two stateless web app pods.
- Creates ReplicaSets underneath.
- Handles rolling updates.
- Replaces failed pods.

Why our app needs it:

FastAPI app is stateless from Kubernetes' perspective. It can run multiple interchangeable replicas behind one Service.

Important pieces:

### Replicas

```yaml
replicas: 2
```

Two pods give basic availability and allow rolling updates.

### Selector

```yaml
selector:
  matchLabels:
    app.kubernetes.io/component: web
```

Deployment owns pods matching this selector. This selector is immutable after creation, so design labels carefully.

### ServiceAccount

```yaml
serviceAccountName: interview-app
```

Connects the pod to IRSA.

### ConfigMap env

```yaml
- name: APP_ENV
  valueFrom:
    configMapKeyRef:
      name: interview-app
      key: APP_ENV
```

Reads non-secret config.

### Secret env

```yaml
- name: DEMO_API_KEY
  valueFrom:
    secretKeyRef:
      name: interview-app
      key: DEMO_API_KEY
      optional: true
```

Reads sensitive-ish config.

### Downward API

```yaml
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```

Lets the app know its own pod metadata.

Why Downward API is useful:

- Logging.
- Debugging.
- Tracing.
- Showing pod/node identity in app responses.

### Probes

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: http
readinessProbe:
  httpGet:
    path: /readyz
    port: http
startupProbe:
  httpGet:
    path: /healthz
    port: http
```

Liveness:

- If it fails repeatedly, kubelet restarts the container.
- Should detect dead process/deadlock.

Readiness:

- If it fails, pod stays running but is removed from Service endpoints.
- In our lab, readiness depends on Redis.

Startup:

- Gives slow-starting apps time before liveness begins killing them.

Interview line:

> A pod can be Running but not Ready. Running is process state; Ready is traffic eligibility.

### Resources

```yaml
resources:
  limits:
    cpu: 500m
    memory: 384Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

Requests:

- Used by scheduler.
- Used by HPA CPU utilization calculations.

Limits:

- CPU limit throttles.
- Memory limit can cause OOMKilled.

Interview line:

> Requests are for scheduling and reservation. Limits are enforcement boundaries.

### Security context

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 100
```

Why:

- Reduce container privilege.
- Avoid running as root.
- Reduce blast radius if app is compromised.

Common Deployment issues:

- `ImagePullBackOff`: image problem.
- `CrashLoopBackOff`: app starts and exits.
- `Running` but `0/1 Ready`: readiness problem.
- `Pending`: scheduler/resource/storage problem.
- `OOMKilled`: memory limit exceeded.

Debug:

```bash
kubectl get deploy,rs,pods -n interview
kubectl describe deploy interview-app -n interview
kubectl describe pod <pod> -n interview
kubectl logs <pod> -n interview
kubectl logs <pod> -n interview --previous
```

## 14. HPA

Template file:

```text
charts/interview-app/templates/hpa.yaml
```

Rendered:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: interview-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: interview-app
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 120
```

What it does:

- Watches CPU utilization.
- Scales Deployment between 2 and 5 replicas.

Why our app needs it:

For practice. The `/burn` endpoint burns CPU so we can trigger autoscaling.

Important:

HPA needs:

- metrics-server.
- CPU requests on pods.

Why CPU request matters:

If request is `100m` and pod uses `60m`, utilization is 60 percent. HPA target is based on percent of request, not percent of node CPU.

Debug:

```bash
kubectl get hpa -n interview
kubectl describe hpa interview-app -n interview
kubectl top pods -n interview
```

Test:

```bash
kubectl run load -n interview --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://interview-app.interview.svc.cluster.local/burn?seconds=3; done'
kubectl get hpa -n interview -w
```

Clean:

```bash
kubectl delete pod load -n interview --ignore-not-found=true
```

Interview line:

> HPA is workload scaling. It does not add nodes. If HPA creates more pods than the cluster can schedule, Cluster Autoscaler is needed to add capacity.

## 15. StatefulSet

Template file:

```text
charts/interview-app/templates/redis-statefulset.yaml
```

Rendered core:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: interview-app-redis
spec:
  serviceName: interview-app-redis
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: redis
  template:
    metadata:
      labels:
        app.kubernetes.io/component: redis
    spec:
      securityContext:
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: redis
          image: "public.ecr.aws/docker/library/redis:7.4-alpine"
          args:
            - redis-server
            - --appendonly
            - "yes"
            - --dir
            - /data
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: interview-gp3
        resources:
          requests:
            storage: 2Gi
```

What it does:

- Runs Redis as a stateful workload.
- Gives the pod a stable name: `interview-app-redis-0`.
- Gives it a stable PVC: `data-interview-app-redis-0`.
- Persists Redis append-only data under `/data`.

Why our app needs it:

The FastAPI app uses Redis for `/redis/incr`. Redis needs stable storage if we want the counter to survive pod restart.

Deployment vs StatefulSet:

Deployment:

- Pods are interchangeable.
- Pod names are not stable.
- Usually no stable per-pod storage.

StatefulSet:

- Stable pod identity.
- Stable storage per replica.
- Ordered rollout.
- Useful for databases, queues, clustered systems.

Real issue we faced:

Redis crashed because it could not change ownership/write properly on `/data`. PVC was bound, EBS existed, but the container still failed.

Lesson:

> Bound storage does not guarantee the application can write. Always check pod logs, volume mount permissions, security context, fsGroup, and image behavior.

Debug:

```bash
kubectl get sts,pod,pvc,pv -n interview
kubectl describe pod interview-app-redis-0 -n interview
kubectl logs interview-app-redis-0 -n interview
kubectl describe pvc data-interview-app-redis-0 -n interview
```

## 16. Ingress

Template file:

```text
charts/interview-app/templates/ingress.yaml
```

Rendered:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: interview-app
  annotations:
    alb.ingress.kubernetes.io/group.name: interview-lab
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/success-codes: "200"
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:us-east-1:923988301700:certificate/a6063a6f-0f64-4f83-8d68-279354e69da2"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  ingressClassName: alb
  rules:
    - host: "app.tanscape.online"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: interview-app
                port:
                  name: http
```

What it does:

- Defines HTTP/HTTPS routing.
- AWS Load Balancer Controller watches this object.
- Controller creates AWS ALB, listeners, target groups, security group rules, and TargetGroupBinding.

Why our app needs it:

Without Ingress, the app is only reachable inside the cluster through ClusterIP Service. Ingress exposes it publicly through `https://app.tanscape.online`.

Important annotations:

- `scheme: internet-facing`: public ALB.
- `target-type: ip`: ALB targets pod IPs directly.
- `healthcheck-path: /healthz`: ALB target health check path.
- `certificate-arn`: ACM certificate for HTTPS.
- `ssl-redirect: "443"`: redirect HTTP to HTTPS.

Ingress vs Service:

- Service gives stable internal access to pods.
- Ingress gives HTTP routing from outside the cluster.
- Ingress needs a controller.

Common issues:

- Ingress has no address: controller/IAM/subnet tags/class issue.
- ALB 503: no healthy targets, bad Service selector, readiness failure, wrong port.
- TLS failure: wrong certificate region, DNS validation issue, hostname mismatch.

Debug:

```bash
kubectl get ingress -n interview
kubectl describe ingress interview-app -n interview
kubectl get targetgroupbinding -n interview
kubectl describe targetgroupbinding -n interview
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

Interview line:

> Ingress is declarative intent. The AWS Load Balancer Controller reconciles that intent into AWS ALB infrastructure.

## 17. VPA

Template file:

```text
charts/interview-app/templates/vpa.yaml
```

Status in this lab:

```yaml
vpa:
  enabled: false
```

Why disabled:

- VPA requires CRDs and controller.
- If we enable VPA without installing those CRDs, Helm/Kubernetes will fail because `VerticalPodAutoscaler` kind is unknown.

Concept:

- HPA changes replica count.
- VPA changes CPU/memory requests.
- Cluster Autoscaler changes node count.

Interview line:

> VPA can be useful for right-sizing resources, but in auto mode it may evict pods. I would be careful using it with latency-sensitive workloads or together with HPA on CPU.

## 18. Practice PVC

Template file:

```text
charts/interview-app/templates/practice-pvc.yaml
```

Status in this lab:

```yaml
practicePvc:
  enabled: false
```

Why it exists:

- To practice a standalone PVC separate from the Redis StatefulSet.

Concept:

PVC does not by itself make data useful. A pod must mount it.

## 19. How The Objects Work Together

Startup order conceptually:

1. Namespace exists.
2. Quota and LimitRange apply guardrails.
3. ServiceAccount is created.
4. ConfigMap and Secret are created.
5. StorageClass exists for dynamic volumes.
6. Redis StatefulSet creates PVC.
7. EBS CSI provisions EBS PV.
8. Redis pod starts and mounts `/data`.
9. App Deployment starts.
10. App readiness checks Redis.
11. Service points to ready app pods.
12. Ingress routes ALB traffic to Service.
13. HPA watches metrics and may scale Deployment.
14. NetworkPolicy restricts traffic.

Important nuance:

Kubernetes applies manifests declaratively. It does not strictly "run steps" like a script. Controllers continuously reconcile desired state to actual state.

Interview line:

> Kubernetes is controller-driven. We declare desired state, and controllers like Deployment controller, StatefulSet controller, HPA controller, scheduler, kubelet, CSI controller, and AWS Load Balancer Controller reconcile toward that state.

## 20. Current Lab Health Commands

```bash
kubectl get nodes -o wide
kubectl get pods -n interview -o wide
kubectl get deploy,rs,sts,ds,svc,endpoints,pvc,hpa,ingress,networkpolicy -n interview
kubectl get storageclass,pv
curl -s https://app.tanscape.online/
curl -s https://app.tanscape.online/readyz
curl -s https://app.tanscape.online/aws/identity
curl -s https://app.tanscape.online/redis/incr
```

