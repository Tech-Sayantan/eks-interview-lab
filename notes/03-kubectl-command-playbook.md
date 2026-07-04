# 03 - kubectl Command Playbook And Interview Drills

This chapter is a practical command reference. Do not memorize blindly. Learn the pattern:

```text
get -> describe -> logs -> events -> exec -> fix -> rollout verify
```

## 1. Cluster And Context

Show current context:

```bash
kubectl config current-context
kubectl config get-contexts
```

Use a context:

```bash
kubectl config use-context <context-name>
```

Check nodes:

```bash
kubectl get nodes
kubectl get nodes -o wide
kubectl describe node <node-name>
```

What to look for:

- `Ready` status.
- Kubernetes version.
- internal/private IP.
- instance type.
- taints.
- allocatable CPU/memory.
- conditions like MemoryPressure, DiskPressure, PIDPressure.

Interview scenario:

Question: "Pods are Pending. Where do you start?"

Answer:

> I check nodes first, then pod events. Pending often means scheduling failed due to resources, taints, affinity, node selector, PVC, or quota.

## 2. Namespace Commands

List namespaces:

```bash
kubectl get ns
```

Get all common objects in namespace:

```bash
kubectl get all -n interview
```

Get important lab objects:

```bash
kubectl get deploy,rs,pods,sts,ds,svc,endpoints,pvc,hpa,ingress,networkpolicy -n interview
```

Tip:

`kubectl get all` does not show everything. It misses objects like Ingress, PVC, NetworkPolicy, ConfigMap, Secret, ResourceQuota, LimitRange, and PDB.

Better command:

```bash
kubectl get deploy,rs,pods,sts,ds,svc,endpoints,pvc,hpa,ingress,networkpolicy,quota,limitrange,pdb -n interview
```

## 3. Pods

List pods:

```bash
kubectl get pods -n interview
kubectl get pods -n interview -o wide
kubectl get pods -n interview --show-labels
```

Describe pod:

```bash
kubectl describe pod <pod-name> -n interview
```

Logs:

```bash
kubectl logs <pod-name> -n interview
kubectl logs <pod-name> -n interview --previous
kubectl logs deploy/interview-app -n interview
kubectl logs statefulset/interview-app-redis -n interview
```

Why `--previous` matters:

If a container is crashing and restarting, current logs may be empty. `--previous` shows logs from the last crashed container.

Exec:

```bash
kubectl exec -it <pod-name> -n interview -- sh
kubectl exec -n interview deploy/interview-app -- env
```

Events:

```bash
kubectl get events -n interview --sort-by=.lastTimestamp
```

## 4. Deployment Commands

Get:

```bash
kubectl get deploy -n interview
kubectl describe deploy interview-app -n interview
```

Rollout status:

```bash
kubectl rollout status deployment/interview-app -n interview
```

Restart:

```bash
kubectl rollout restart deployment/interview-app -n interview
```

History:

```bash
kubectl rollout history deployment/interview-app -n interview
```

Undo:

```bash
kubectl rollout undo deployment/interview-app -n interview
```

Scale:

```bash
kubectl scale deployment interview-app -n interview --replicas=3
```

Watch ReplicaSets:

```bash
kubectl get rs -n interview
```

Interview scenario:

Question: "How does Deployment update pods?"

Answer:

> Deployment creates a new ReplicaSet for the new pod template and gradually scales old ReplicaSet down and new ReplicaSet up, based on rolling update settings.

## 5. Service And Endpoints

Get Service:

```bash
kubectl get svc -n interview
kubectl describe svc interview-app -n interview
```

Get endpoints:

```bash
kubectl get endpoints interview-app -n interview
kubectl get endpointslice -n interview
```

Inside-cluster test:

```bash
kubectl run curl-test -n interview --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/curlimages/curl:8.10.1 \
  -- curl -s http://interview-app/readyz
```

Common issue:

Service exists but endpoint list is empty.

Causes:

- Selector mismatch.
- Pods not Ready.
- Pods in different namespace.

Interview line:

> For Service problems, I immediately compare Service selectors against pod labels and then check endpoints.

## 6. Ingress And ALB

Get Ingress:

```bash
kubectl get ingress -n interview
kubectl describe ingress interview-app -n interview
```

TargetGroupBinding:

```bash
kubectl get targetgroupbinding -n interview
kubectl describe targetgroupbinding -n interview
```

Controller logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

AWS side:

```bash
aws elbv2 describe-load-balancers --region us-east-1 --profile eks-lab
aws elbv2 describe-target-groups --region us-east-1 --profile eks-lab
```

Public test:

```bash
curl -i https://app.tanscape.online/healthz
curl -i https://app.tanscape.online/readyz
```

Interview scenario:

Question: "ALB returns 503. How do you debug?"

Answer:

> I check Ingress address, controller logs, TargetGroupBinding, Service endpoints, pod readiness, and ALB target group health. In many cases the ALB is fine but Kubernetes has no ready endpoints.

## 7. ConfigMap And Secret

Get:

```bash
kubectl get configmap -n interview
kubectl get secret -n interview
```

Describe:

```bash
kubectl describe configmap interview-app -n interview
kubectl describe secret interview-app -n interview
```

View ConfigMap:

```bash
kubectl get configmap interview-app -n interview -o yaml
```

Do not casually print secrets in real environments.

Check from app:

```bash
curl -s https://app.tanscape.online/config
curl -s https://app.tanscape.online/secret-check
```

Interview line:

> ConfigMap is for non-sensitive configuration. Secret is for sensitive data, but it still needs RBAC, encryption at rest, and careful handling.

## 8. ServiceAccount And IRSA

Get ServiceAccount:

```bash
kubectl get sa interview-app -n interview -o yaml
```

Check pod env:

```bash
kubectl exec -n interview deploy/interview-app -- env | grep AWS
```

Call identity endpoint:

```bash
curl -s https://app.tanscape.online/aws/identity
```

AWS role:

```bash
aws iam get-role \
  --role-name interview-eks-interview-app-irsa \
  --profile eks-lab
```

Interview scenario:

Question: "Pod gets AccessDenied from AWS. What do you check?"

Answer:

> I check ServiceAccount annotation, pod serviceAccountName, whether the pod restarted after annotation changes, IAM trust policy subject, OIDC provider, and IAM permissions attached to the role.

## 9. StatefulSet, PVC, PV, StorageClass

Get:

```bash
kubectl get sts -n interview
kubectl get pods -n interview | grep redis
kubectl get pvc -n interview
kubectl get pv
kubectl get storageclass
```

Describe:

```bash
kubectl describe sts interview-app-redis -n interview
kubectl describe pod interview-app-redis-0 -n interview
kubectl describe pvc data-interview-app-redis-0 -n interview
```

Logs:

```bash
kubectl logs interview-app-redis-0 -n interview
```

Test Redis through app:

```bash
curl -s https://app.tanscape.online/redis/incr
```

Interview scenario:

Question: "PVC is Pending. What do you check?"

Answer:

> I check StorageClass, CSI driver pods, PVC events, node/AZ constraints, and IAM permissions for the CSI driver.

Question: "PVC is Bound but pod crashes."

Answer:

> Then provisioning worked, so I check pod logs, mount path, filesystem permissions, securityContext, fsGroup, and application startup behavior.

## 10. HPA

Get:

```bash
kubectl get hpa -n interview
kubectl describe hpa interview-app -n interview
```

Metrics:

```bash
kubectl top nodes
kubectl top pods -n interview
```

Load test:

```bash
kubectl run load -n interview --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- /bin/sh -c 'while true; do wget -q -O- http://interview-app.interview.svc.cluster.local/burn?seconds=3; done'
kubectl get hpa -n interview -w
```

Clean:

```bash
kubectl delete pod load -n interview --ignore-not-found=true
```

Interview line:

> HPA requires metrics and resource requests. If CPU request is missing, CPU utilization percentage cannot be calculated properly.

## 11. NetworkPolicy

Get:

```bash
kubectl get networkpolicy -n interview
kubectl describe networkpolicy interview-app-web -n interview
kubectl describe networkpolicy interview-app-redis -n interview
```

CNI check:

```bash
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl describe daemonset aws-node -n kube-system | grep -i network -A5
```

Test blocked Redis access from unrelated pod:

```bash
kubectl run net-test -n interview --rm -i --restart=Never \
  --image=public.ecr.aws/docker/library/busybox:1.36 \
  -- sh -c 'nc -vz -w 3 interview-app-redis 6379'
```

Interview line:

> NetworkPolicy is label-based and additive. It only works if the CNI enforces it.

## 12. DaemonSet

Get:

```bash
kubectl get ds -n interview
kubectl get pods -n interview -l app.kubernetes.io/component=node-reporter -o wide
```

Logs:

```bash
kubectl logs -n interview -l app.kubernetes.io/component=node-reporter --tail=20
```

Interview line:

> DaemonSet is for one pod per node use cases like logging, monitoring, CNI, CSI node plugin, or security agents.

## 13. ResourceQuota, LimitRange, PDB

Get:

```bash
kubectl get quota,limitrange,pdb -n interview
kubectl describe quota interview-app -n interview
kubectl describe limitrange interview-app -n interview
kubectl describe pdb interview-app -n interview
```

Interview line:

> Quota caps total namespace usage, LimitRange applies container-level defaults/constraints, and PDB protects availability during voluntary disruptions.

## 14. Failure Drill: Readiness Failure

Break Redis:

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=0
kubectl get pods -n interview
curl -i https://app.tanscape.online/readyz
```

Observe:

```bash
kubectl describe deploy interview-app -n interview
kubectl get endpoints interview-app -n interview
```

Recover:

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=1
kubectl rollout status statefulset/interview-app-redis -n interview
kubectl rollout restart deployment/interview-app -n interview
```

Learning:

Pod can be alive but not ready.

## 15. Failure Drill: CrashLoopBackOff

Break:

```bash
kubectl patch deployment interview-app -n interview --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["python","-c","import sys; sys.exit(1)"]}]'
```

Observe:

```bash
kubectl get pods -n interview -w
kubectl logs -n interview deploy/interview-app --previous
kubectl describe pod -n interview -l app.kubernetes.io/component=web
```

Recover:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  -f manual-values/my-values.yaml \
  --wait \
  --timeout 10m
```

Learning:

CrashLoopBackOff means the container starts, exits, restarts, and repeats.

## 16. Failure Drill: ImagePullBackOff

Break:

```bash
kubectl set image deployment/interview-app app=bad-image-does-not-exist:bad -n interview
```

Observe:

```bash
kubectl get pods -n interview -w
kubectl describe pod -n interview -l app.kubernetes.io/component=web
```

Recover:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  -f manual-values/my-values.yaml \
  --wait \
  --timeout 10m
```

Learning:

ImagePullBackOff is usually registry, repo, tag, auth, network, or architecture problem.

## 17. Failure Drill: ALB/Ingress 503

Break readiness by scaling Redis down:

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=0
```

Observe:

```bash
curl -i https://app.tanscape.online/readyz
kubectl get endpoints interview-app -n interview
kubectl describe ingress interview-app -n interview
kubectl describe targetgroupbinding -n interview
```

Recover:

```bash
kubectl scale statefulset interview-app-redis -n interview --replicas=1
kubectl rollout status statefulset/interview-app-redis -n interview
```

Learning:

External ALB symptoms often start from internal pod readiness or Service endpoints.

## 18. Failure Drill: Quota

Try creating too many pods:

```bash
kubectl create deployment quota-test -n interview \
  --image=public.ecr.aws/docker/library/busybox:1.36 \
  -- sleep 3600

kubectl scale deployment quota-test -n interview --replicas=30
kubectl get rs,pods -n interview
kubectl get events -n interview --sort-by=.lastTimestamp
```

Clean:

```bash
kubectl delete deployment quota-test -n interview --ignore-not-found=true
```

Learning:

Admission controllers can reject object creation or pod creation due to quota.

## 19. Failure Drill: Rolling Update And Rollback

Change app message:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  -f manual-values/my-values.yaml \
  --set config.appMessage="rolling update practice" \
  --wait \
  --timeout 10m
```

Observe:

```bash
kubectl rollout status deployment/interview-app -n interview
kubectl get rs -n interview
curl -s https://app.tanscape.online/config
helm history interview-app -n interview
```

Rollback:

```bash
helm history interview-app -n interview
helm rollback interview-app <previous-good-revision> -n interview
```

Learning:

Kubernetes Deployment rollout and Helm release history are related but not identical.

## 20. High-Value Interview Command Patterns

### "Show me what is running"

```bash
kubectl get pods -A -o wide
```

### "Why is this pod broken?"

```bash
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
```

### "Why is Service not routing?"

```bash
kubectl get svc,endpoints,endpointslice -n <ns>
kubectl get pods -n <ns> --show-labels
```

### "Why is Ingress not working?"

```bash
kubectl describe ingress <name> -n <ns>
kubectl logs -n kube-system deployment/aws-load-balancer-controller
kubectl get targetgroupbinding -n <ns>
```

### "Why is storage broken?"

```bash
kubectl get storageclass,pv,pvc -A
kubectl describe pvc <pvc> -n <ns>
kubectl logs -n kube-system deployment/ebs-csi-controller
```

### "Why is autoscaling not working?"

```bash
kubectl top pods -n <ns>
kubectl describe hpa <hpa> -n <ns>
```

### "What changed in Helm?"

```bash
helm history <release> -n <ns>
helm get values <release> -n <ns>
helm get manifest <release> -n <ns>
```

## 21. A Good Debugging Story Structure

When interviewer asks "How would you debug X?", answer like this:

1. State the symptom.
2. Separate layers.
3. Check the fastest signal.
4. Use commands.
5. Name likely root causes.
6. Explain fix and prevention.

Example:

> If ALB returns 503, I separate AWS ALB, Kubernetes Ingress, Service, endpoints, and pod readiness. I first check `kubectl get ingress`, then `kubectl get endpoints`, then pod readiness and AWS Load Balancer Controller logs. If endpoints are empty, I check Service selectors and readiness probes. If endpoints exist but ALB targets are unhealthy, I inspect TargetGroupBinding and ALB target health.

