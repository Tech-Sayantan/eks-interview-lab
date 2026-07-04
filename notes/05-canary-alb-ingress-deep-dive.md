# 05 - Canary Deployment With AWS ALB Ingress

This chapter explains the canary setup added to the lab.

## 1. What Canary Means

A canary deployment releases a new version to a small percentage of traffic before sending everyone to it.

Example:

```text
90 percent traffic -> stable version
10 percent traffic -> canary version
```

If canary looks healthy, increase:

```text
90/10 -> 75/25 -> 50/50 -> 0/100
```

If canary looks bad, rollback:

```text
90/10 -> 100/0
```

Interview line:

> Canary reduces blast radius. Instead of exposing all users to a new version immediately, we expose a small percentage first and promote only if metrics look healthy.

## 2. What We Implemented

This lab uses **manual ALB weighted canary** through AWS Load Balancer Controller annotations.

Objects:

```text
Stable Deployment: interview-app
Stable Service: interview-app

Canary Deployment: interview-app-canary
Canary Service: interview-app-canary

Ingress weighted action: interview-app-weighted
```

Traffic path:

```text
User
  -> Route 53
  -> ALB
  -> Ingress rule
  -> weighted forward action
  -> stable target group and canary target group
  -> stable/canary pods
```

## 3. Important ALB Rule

AWS Load Balancer Controller supports custom actions through this annotation pattern:

```yaml
alb.ingress.kubernetes.io/actions.<action-name>
```

Important rules:

- The annotation action name must match the Ingress backend service name.
- The Ingress backend service port must be `use-annotation`.
- The action JSON can forward to multiple Kubernetes Services with weights.

In our rendered manifest:

```yaml
alb.ingress.kubernetes.io/actions.interview-app-weighted: >
  {
    "type": "forward",
    "forwardConfig": {
      "targetGroups": [
        {
          "serviceName": "interview-app",
          "servicePort": "80",
          "weight": 90
        },
        {
          "serviceName": "interview-app-canary",
          "servicePort": "80",
          "weight": 10
        }
      ]
    }
  }
```

And the Ingress backend becomes:

```yaml
backend:
  service:
    name: interview-app-weighted
    port:
      name: use-annotation
```

Important:

`interview-app-weighted` is not a normal Kubernetes Service. It is an action name that AWS Load Balancer Controller understands.

## 4. Helm Values

Canary is disabled by default:

```yaml
canary:
  enabled: false
  stableWeight: 90
  weight: 10
  replicaCount: 1
  config:
    appEnv: "canary"
    appMessage: "CANARY - weighted ALB traffic split"
```

Enable canary:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  --reuse-values \
  --set canary.enabled=true \
  --set canary.stableWeight=90 \
  --set canary.weight=10 \
  --wait \
  --timeout 10m
```

Change weights:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  --reuse-values \
  --set canary.enabled=true \
  --set canary.stableWeight=75 \
  --set canary.weight=25 \
  --wait \
  --timeout 10m
```

Disable canary:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  --reuse-values \
  --set canary.enabled=false \
  --wait \
  --timeout 10m
```

## 5. Why We Need Two Services

ALB splits traffic between target groups.

In AWS Load Balancer Controller, each Kubernetes Service backend becomes a target group.

So we need:

```text
interview-app         -> stable target group
interview-app-canary  -> canary target group
```

Then the ALB forward action splits between those target groups.

## 6. Why This Is Not The Same As RollingUpdate

RollingUpdate:

- One Deployment.
- Kubernetes replaces pods gradually.
- Service points to one set of labels.
- Traffic is not intentionally split by percentage.

Canary:

- Stable and canary exist at the same time.
- Separate Services/target groups.
- ALB intentionally splits traffic by weight.
- You can observe canary before promotion.

Interview line:

> Rolling update controls pod replacement. Canary controls traffic exposure.

## 7. Manual Canary vs Argo Rollouts

Our setup:

- Manual Helm values change weights.
- Manual observation.
- Manual rollback.

Argo Rollouts or Flagger:

- Automates weight changes.
- Pauses between steps.
- Runs metric analysis.
- Automatically rolls back on bad metrics.

Interview line:

> ALB weighted routing gives the traffic-splitting primitive. Argo Rollouts adds progressive delivery automation and analysis.

## 8. How To Verify

Check objects:

```bash
kubectl get deploy,svc,ingress,targetgroupbinding -n interview
kubectl describe ingress interview-app -n interview
```

Call the app repeatedly:

```bash
for i in {1..30}; do
  curl -s https://app.tanscape.online/api/info | jq -r '.message'
done | sort | uniq -c
```

Expected with 90/10:

```text
Most responses: deployed by GitHub Actions OIDC
Some responses: CANARY - weighted ALB traffic split
```

The ratio will not be exact with only 30 requests. Over many requests it gets closer.

## 9. Rollback

Fast rollback to stable only:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  --reuse-values \
  --set canary.enabled=false \
  --wait \
  --timeout 10m
```

Or set weights:

```bash
helm upgrade --install interview-app charts/interview-app \
  -n interview \
  --reuse-values \
  --set canary.enabled=true \
  --set canary.stableWeight=100 \
  --set canary.weight=0 \
  --wait \
  --timeout 10m
```

Difference:

- `canary.enabled=false` removes canary resources.
- `100/0` keeps canary deployed but sends no traffic.

## 10. Production Considerations

Before production canary, define:

- Success metrics.
- Error-rate threshold.
- Latency threshold.
- Time window.
- Rollback trigger.
- Who approves promotion.
- Whether sessions need stickiness.
- Whether database migrations are backward compatible.
- How logs and metrics distinguish stable vs canary.

Important interview answer:

> Canary is not just routing. It needs observability and rollback criteria. A 10 percent canary without metrics is just a slower risky deployment.

## 11. Useful Sources

- AWS Load Balancer Controller Ingress annotations.
- AWS Load Balancer Controller blue/green and weighted target group use case.
- Argo Rollouts ALB traffic management documentation.

