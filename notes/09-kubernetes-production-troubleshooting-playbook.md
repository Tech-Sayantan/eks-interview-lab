# Kubernetes Production Troubleshooting Playbook

This is the playbook to revise before interviews. The goal is to reason by lifecycle instead of randomly running commands.

## The Golden Flow

When someone says "the app is down", debug from outside to inside:

```text
User symptom
-> DNS
-> TLS/certificate
-> Load balancer
-> Ingress
-> Service
-> Endpoints/EndpointSlices
-> Pods
-> Logs
-> Events
-> Deployment/ReplicaSet
-> Nodes/scheduling
-> Storage
-> NetworkPolicy
-> IAM/secrets/dependencies
```

Interview line:

"I start from the user-facing symptom, then follow traffic inward until I find the first broken layer."

## First Commands

```bash
curl -i https://app.tanscape.online/
curl -i https://app.tanscape.online/healthz
curl -i https://app.tanscape.online/readyz

kubectl get ingress,svc,endpoints,endpointslice -n interview
kubectl get pods -n interview -o wide
kubectl get events -n interview --sort-by=.lastTimestamp | tail -n 30
kubectl get deploy,rs,hpa,pdb -n interview
```

## Symptom: DNS Failure

Signs:

- browser cannot resolve host
- `curl` says could not resolve host
- `dig` returns no answer

Commands:

```bash
dig app.tanscape.online
nslookup app.tanscape.online
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

Likely causes:

- nameservers not delegated from GoDaddy to Route 53
- missing A alias record
- wrong hosted zone
- DNS propagation delay

## Symptom: TLS/Certificate Error

Signs:

- browser certificate warning
- `curl` TLS error
- HTTPS listener not working

Commands:

```bash
kubectl describe ingress interview-app -n interview
aws acm describe-certificate --region us-east-1 --certificate-arn <arn>
aws elbv2 describe-listeners --load-balancer-arn <alb-arn>
```

Likely causes:

- ACM certificate not issued
- certificate in wrong region
- wrong certificate ARN in Ingress annotation
- ALB listener missing HTTPS

## Symptom: ALB Returns 503

Signs:

- DNS works
- TLS works
- ALB responds
- app returns `503`

Likely causes:

- target group has no healthy targets
- Service has no ready endpoints
- readiness probes failing
- app dependency down

Commands:

```bash
kubectl get ingress -n interview
kubectl describe ingress interview-app -n interview
kubectl get targetgroupbinding -n interview
kubectl get endpoints interview-app -n interview
kubectl get pods -n interview
```

Interview line:

"An ALB 503 often means the load balancer has no healthy backend targets, so I check target groups, Service endpoints, and pod readiness."

## Symptom: Pod Pending

Signs:

```text
STATUS Pending
```

Use:

```bash
kubectl describe pod <pod> -n interview
```

Look at events.

Common causes:

- insufficient CPU/memory
- node selector mismatch
- taints without tolerations
- PVC cannot bind
- EBS PV node affinity mismatch
- node is cordoned
- namespace quota exceeded
- max pod density reached

Important messages:

- `0/2 nodes are available`
- `Too many pods`
- `didn't match PersistentVolume's node affinity`
- `node(s) had untolerated taint`
- `Insufficient cpu`
- `pod has unbound immediate PersistentVolumeClaims`

## Symptom: CrashLoopBackOff

Meaning:

The container starts, then exits repeatedly.

Commands:

```bash
kubectl describe pod <pod> -n interview
kubectl logs <pod> -n interview
kubectl logs <pod> -n interview --previous
kubectl get pod <pod> -n interview -o yaml
```

Likely causes:

- app exception on startup
- bad command/args
- missing env var
- bad config
- cannot connect to required startup dependency
- permission issue
- read-only filesystem issue

Important:

If the process exits before logging, `logs --previous` can be empty. Then pod events and container command become more important.

## Symptom: ImagePullBackOff

Meaning:

Kubernetes scheduled the pod, but the node cannot pull the image.

Commands:

```bash
kubectl describe pod <pod> -n interview
aws ecr describe-images --repository-name interview-app --region us-east-1
```

Likely causes:

- tag does not exist
- wrong registry
- node lacks ECR pull permission
- private registry auth missing
- network egress problem
- image architecture mismatch

Interview line:

"For image pull issues, logs usually do not exist because the container never started. Events are the source of truth."

## Symptom: Running But Not Ready

Meaning:

The process exists, but Kubernetes should not send traffic to it.

Commands:

```bash
kubectl describe pod <pod> -n interview
kubectl get endpoints interview-app -n interview
curl -i https://app.tanscape.online/readyz
```

Likely causes:

- readiness endpoint returns non-200
- dependency down
- app warming up
- bad probe path/port
- NetworkPolicy blocks dependency
- Secret/ConfigMap issue

Important:

`Running` is not equal to `Ready`.

## Probes

### Startup Probe

Use for slow-starting apps.

If startup probe fails repeatedly, kubelet kills the container.

### Readiness Probe

Controls whether pod receives traffic.

Good readiness checks:

- app can serve requests
- critical dependencies available if required to serve

### Liveness Probe

Controls whether kubelet restarts the container.

Avoid putting every dependency in liveness. If Redis goes down, restarting all app pods may make the incident worse.

Interview line:

"Readiness protects traffic. Liveness recovers stuck processes. Startup protects slow boot."

## Deployment And ReplicaSet Debugging

Commands:

```bash
kubectl get deploy,rs,pods -n interview
kubectl describe deployment interview-app -n interview
kubectl rollout status deployment/interview-app -n interview
kubectl rollout history deployment/interview-app -n interview
```

Key fields:

- desired replicas
- updated replicas
- ready replicas
- available replicas
- old ReplicaSets
- rollout conditions

If rollout is stuck:

```bash
kubectl describe rs <replicaset> -n interview
kubectl describe pod <new-pod> -n interview
```

## Helm Debugging

Commands:

```bash
helm list -n interview
helm history interview-app -n interview
helm get values interview-app -n interview --all
helm get manifest interview-app -n interview
helm lint charts/interview-app -f values.yaml
helm template interview-app charts/interview-app -f values.yaml
```

Common issues:

- wrong values file
- wrong image tag
- resource already exists but not owned by Helm
- immutable field changed
- upgrade timed out
- chart renders invalid YAML

Rollback:

```bash
helm rollback interview-app <revision> -n interview --wait --timeout 5m
```

## Storage Debugging

Commands:

```bash
kubectl get sts,pvc,pv,storageclass -n interview
kubectl describe pod interview-app-redis-0 -n interview
kubectl describe pvc data-interview-app-redis-0 -n interview
kubectl describe pv <pv-name>
kubectl get volumeattachment
kubectl get nodes -L topology.kubernetes.io/zone
```

Common issues:

- PVC pending
- EBS volume in wrong AZ
- Multi-Attach error
- volume detach delay
- storage class missing
- reclaim policy surprises
- deleted PVC deletes PV because reclaim policy is `Delete`

Interview line:

"For EBS-backed StatefulSets, I always check PV node affinity and node AZ labels."

## Network Debugging

Commands:

```bash
kubectl get networkpolicy -n interview
kubectl describe networkpolicy -n interview
kubectl run netshoot -n interview --rm -it --image=nicolaka/netshoot --restart=Never -- /bin/bash
```

Inside debug pod:

```bash
nslookup interview-app
curl -i http://interview-app
nc -vz interview-app-redis 6379
```

Common issues:

- DNS blocked by egress policy
- Redis blocked by ingress policy
- external HTTPS blocked
- policy selects wrong pods
- CNI does not enforce NetworkPolicy

## IAM And IRSA Debugging

Commands:

```bash
kubectl get sa interview-app -n interview -o yaml
kubectl describe pod <pod> -n interview
curl -fsS https://app.tanscape.online/aws/identity
curl -fsS https://app.tanscape.online/secret-manager-check
```

Check pod env:

- `AWS_ROLE_ARN`
- `AWS_WEB_IDENTITY_TOKEN_FILE`
- `AWS_STS_REGIONAL_ENDPOINTS`

Common issues:

- service account missing role annotation
- IAM trust policy wrong namespace/service account
- OIDC provider missing
- IAM policy lacks required action
- app uses wrong AWS region

Interview line:

"With IRSA, the pod assumes an IAM role through a projected service account token. I debug both the Kubernetes service account annotation and the IAM trust policy."

## ResourceQuota And LimitRange

Commands:

```bash
kubectl get resourcequota,limitrange -n interview
kubectl describe resourcequota interview-app -n interview
kubectl describe limitrange interview-app -n interview
```

Failure type:

This is usually admission-time failure. The pod may never be created.

Common messages:

- `exceeded quota`
- `must specify limits`
- `forbidden`

Interview line:

"Quota failures happen before scheduling. Pending means accepted but not placed; quota denial means the API request was rejected."

## Node Debugging

Commands:

```bash
kubectl get nodes -o wide
kubectl describe node <node>
kubectl top nodes
kubectl get pods -A -o wide
```

Look for:

- `Ready`
- taints
- allocatable CPU/memory
- pod capacity
- disk pressure
- memory pressure
- node labels
- zone

Important:

Small AWS instances can run out of pod slots because of ENI/IP limits before CPU or memory are full.

## A Strong Interview Debug Answer

"I start with the symptom from outside: DNS, TLS, and ALB response. If ALB returns 503, I inspect Ingress, target groups, Service endpoints, and pod readiness. If pods are not ready, I inspect probes, logs, and events. If pods are pending, I check scheduling events, quota, taints, node capacity, and PVC node affinity. If pods crash, I check logs and previous logs. If AWS access fails, I check IRSA service account annotation, token projection, IAM trust, and policy permissions. I always separate admission failures, scheduling failures, image pull failures, runtime failures, and traffic routing failures."

