# Kubernetes Scheduling, Resilience, And Autoscaling Runbook

This note fills a high-value interview gap:

```text
How does Kubernetes decide where a Pod runs?
Why is my Pod Pending?
How do I keep apps available during node failure or deployment?
How do HPA, VPA, Cluster Autoscaler, and Karpenter relate?
```

## Core Mental Model

Kubernetes does not "just run containers."

It continuously reconciles desired state to actual state.

For a Pod:

```text
API server receives Pod
-> scheduler selects node
-> kubelet pulls image
-> container runtime starts container
-> probes decide availability
-> controllers replace failed Pods
```

Interview line:

"Scheduling is about placing Pods on nodes that satisfy resource, policy, topology, affinity, taint, and volume constraints."

## Scheduler Inputs

The scheduler considers:

- CPU and memory requests
- node capacity and allocatable resources
- node selector
- node affinity
- pod affinity and anti-affinity
- taints and tolerations
- topology spread constraints
- volume zone constraints
- resource quotas
- priority and preemption

If no node fits, Pod stays `Pending`.

## Requests And Limits

Requests:

- used by scheduler
- used by HPA CPU percentage math
- reserve capacity

Limits:

- runtime cap
- CPU can be throttled
- memory limit can cause OOMKilled

Example:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

Interview line:

"Requests are for scheduling and capacity planning. Limits are runtime guardrails."

## QoS Classes

Kubernetes assigns QoS class.

### Guaranteed

Every container has CPU and memory request equal to limit.

Best eviction protection.

### Burstable

At least one request is set, but requests and limits are not all equal.

Common for web apps.

### BestEffort

No requests or limits.

First to be evicted under pressure.

Check:

```bash
kubectl describe pod <pod> -n <namespace> | grep "QoS Class"
```

## Pod Pending

Common causes:

- insufficient CPU/memory
- PVC not bound
- EBS volume in different AZ
- taints not tolerated
- nodeSelector impossible
- affinity/anti-affinity impossible
- namespace quota exceeded
- image pull does not cause Pending; it causes waiting states after scheduling

Commands:

```bash
kubectl describe pod <pod> -n <namespace>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
kubectl describe node <node>
kubectl get quota -n <namespace>
kubectl get pvc -n <namespace>
```

The answer is usually in Pod events.

## nodeSelector

Simple exact label match.

```yaml
nodeSelector:
  workload: apps
```

Node must have:

```bash
kubectl label node <node> workload=apps
```

Use for simple placement.

## Node Affinity

More expressive than `nodeSelector`.

Example:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workload
              operator: In
              values: ["apps"]
```

Hard rule:

`requiredDuringSchedulingIgnoredDuringExecution`

Soft preference:

`preferredDuringSchedulingIgnoredDuringExecution`

## Pod Anti-Affinity

Used to avoid placing replicas together.

Example:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: interview-app
          topologyKey: kubernetes.io/hostname
```

This says:

```text
Prefer spreading app replicas across different nodes.
```

Why useful:

- one node failure should not kill all replicas
- reduces blast radius

## Topology Spread Constraints

Modern preferred way to spread Pods across zones or nodes.

Example:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: interview-app
```

Use:

- spread replicas across AZs
- avoid overloaded nodes
- improve availability

Be careful:

Hard spread rules can make Pods Pending if the cluster cannot satisfy them.

## Taints And Tolerations

Taint is on node:

```bash
kubectl taint nodes <node> dedicated=platform:NoSchedule
```

Toleration is on Pod:

```yaml
tolerations:
  - key: dedicated
    operator: Equal
    value: platform
    effect: NoSchedule
```

Meaning:

```text
Only Pods that tolerate the taint can schedule on that node.
```

Use cases:

- platform/system nodes
- GPU nodes
- spot nodes
- isolated workloads

## EBS And Scheduling

EBS volumes are AZ-scoped.

If a PVC binds to a volume in AZ A, the Pod must run in AZ A.

This can cause Pending if:

- nodes in that AZ are unavailable
- nodeSelector sends Pod to another AZ
- old volume remains in one AZ

StorageClass with `WaitForFirstConsumer` helps because Kubernetes waits to pick the volume zone until the Pod is scheduled.

Interview line:

"EBS is zonal, so storage can become a scheduling constraint."

## PodDisruptionBudget

PDB controls voluntary disruption.

Example:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: interview-app
  namespace: interview
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: interview-app
```

Protects during:

- node drain
- cluster upgrade
- voluntary evictions

Does not protect against:

- node crash
- app crash
- OOMKilled
- involuntary failure

Our teardown lesson:

PDB can block node draining if allowed disruptions are zero.

Interview line:

"PDB improves availability during voluntary disruption, but if configured too strictly it can block upgrades or node drains."

## PriorityClass And Preemption

PriorityClass gives some Pods scheduling priority.

Example:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 100000
globalDefault: false
description: Critical app priority
```

Use carefully.

If high-priority Pods cannot schedule, Kubernetes may preempt lower-priority Pods.

Good for:

- critical platform components
- security agents
- production-critical apps

Risk:

- overuse makes priority meaningless
- can cause disruption to lower-priority workloads

## Evictions And Node Pressure

Kubelet can evict Pods under pressure.

Common pressures:

- memory pressure
- disk pressure
- PID pressure

Eviction order often considers QoS and resource usage.

Check:

```bash
kubectl describe node <node>
kubectl get events -A --sort-by=.lastTimestamp | grep -i eviction
```

## Graceful Shutdown

During termination:

```text
Kubernetes marks Pod terminating
-> removes from Service endpoints after readiness fails/termination starts
-> sends SIGTERM
-> waits terminationGracePeriodSeconds
-> sends SIGKILL if still running
```

Best practices:

- handle SIGTERM
- stop accepting new requests
- finish in-flight requests
- use readiness correctly
- set reasonable termination grace period
- use `preStop` hook only when needed

Example:

```yaml
terminationGracePeriodSeconds: 30
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 5"]
```

Why `sleep` sometimes helps:

It gives load balancer and endpoints time to stop sending traffic before the process exits.

Do not use it blindly.

## Deployment Strategy

Rolling update fields:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

Meaning:

- `maxUnavailable: 0`: keep all old replicas available during rollout
- `maxSurge: 1`: allow one extra Pod temporarily

Good for small apps.

Tradeoff:

- safer rollout
- needs extra capacity during deployment

## HPA

HPA changes replica count.

Needs:

- metrics-server or custom metrics
- resource requests for CPU-based scaling

Common issue:

HPA says `Unknown` because metrics are missing or requests are absent.

Commands:

```bash
kubectl get hpa -A
kubectl describe hpa <name> -n <namespace>
kubectl top pods -n <namespace>
```

## VPA

VPA recommends or changes resource requests.

Modes:

- `Off`: recommendation only
- `Initial`: sets requests at Pod creation
- `Auto`: can evict Pods to apply changes

Production caution:

Do not casually use VPA `Auto` for critical workloads without understanding eviction behavior.

## Cluster Autoscaler

Cluster Autoscaler changes node group size.

It reacts to:

- Pending Pods that cannot schedule due to lack of capacity
- underutilized nodes that can be removed safely

Works with:

- managed node groups
- self-managed Auto Scaling Groups

Needs correct ASG tags and IAM permissions.

## Karpenter

Karpenter provisions nodes dynamically based on unscheduled Pods.

Strengths:

- faster provisioning
- better bin packing
- flexible instance choice
- good for mixed workloads

Difference:

```text
HPA scales Pods.
Cluster Autoscaler/Karpenter scales nodes.
VPA adjusts/recommends Pod requests.
```

## Resilience Checklist

For a production web app:

- at least 2 replicas
- readiness probe
- liveness probe
- startup probe if slow start
- resource requests and limits
- rolling update strategy
- PDB
- topology spread across nodes/AZs
- HPA
- no single-AZ dependency unless accepted
- clear rollback path
- good logs and metrics

## Interview Scenarios

### "Why is my Pod Pending?"

Answer:

"I check Pod events first. Pending usually means the scheduler cannot place the Pod due to resources, taints, affinity, quota, or volume constraints. Then I inspect nodes, quotas, PVCs, and scheduling rules."

### "Why did all replicas go down during node drain?"

Possible reasons:

- only one replica
- no PDB
- replicas colocated on one node
- no topology spread/anti-affinity
- readiness/liveness badly configured
- app cannot tolerate restart

### "Why did rollout hang?"

Possible reasons:

- new Pods not ready
- readiness probe failing
- image pull issue
- insufficient capacity for surge
- PDB conflict
- bad config/secret

Commands:

```bash
kubectl rollout status deployment/<name> -n <namespace>
kubectl describe deployment <name> -n <namespace>
kubectl get rs,pods -n <namespace>
kubectl describe pod <new-pod> -n <namespace>
```

### "How do you safely upgrade nodes?"

Answer:

"I check PDBs, replica counts, pod distribution, daemonsets, and stateful workloads. Then I cordon/drain nodes gradually, monitor app health and ALB target health, and roll back if error rate or latency crosses threshold."

## Final Mental Model

For scheduling/resilience questions, answer in layers:

```text
Can Kubernetes place the Pod?
Can the node run the Pod?
Can the app become Ready?
Can traffic reach only Ready Pods?
Can the system survive failure, drain, or rollout?
Can autoscaling add Pods and nodes when needed?
```

That structure sounds calm and senior.
