# CloudWatch, Observability, Cost Optimization, And Day-2 Operations Runbook

This note covers the production side of EKS: how teams observe clusters, respond to incidents, control cost, and operate applications day to day.

## The Big Picture

Running Kubernetes is not just deploying YAML.

Real production ownership means:

```text
observe
-> alert
-> investigate
-> mitigate
-> fix
-> prevent recurrence
-> optimize cost
-> document and automate
```

For EKS, observability usually combines:

- CloudWatch metrics
- CloudWatch Logs
- Container Insights
- Prometheus metrics
- Grafana dashboards
- distributed tracing
- Kubernetes events
- application logs
- AWS service logs
- cost and usage data

Interview line:

"I separate observability into metrics, logs, traces, events, and cost signals. Metrics tell me what is happening, logs tell me why, traces show request path, and events explain Kubernetes decisions."

## Observability Vocabulary

### Metrics

Numeric time-series data.

Examples:

- CPU usage
- memory usage
- pod restarts
- request latency
- HTTP 5xx count
- ALB target response time
- HPA desired replicas

Use metrics for dashboards, alerts, SLOs, and trend analysis.

### Logs

Text or structured records emitted by apps or infrastructure.

Examples:

- application JSON logs
- NGINX access logs
- kubelet logs
- AWS Load Balancer Controller logs
- CloudTrail audit logs

Use logs for debugging cause and context.

### Traces

Request-level path across services.

Example:

```text
frontend
-> backend API
-> Redis
-> external payment API
```

Use traces when a request crosses multiple services and latency/error source is unclear.

### Events

Kubernetes lifecycle messages.

Examples:

- image pull failed
- readiness probe failed
- pod failed scheduling
- volume attach failed
- deployment scaled

Use events for Kubernetes control-plane decisions.

## CloudWatch In EKS

CloudWatch can collect:

- infrastructure metrics
- Container Insights metrics
- application logs
- Kubernetes control plane logs
- custom metrics
- alarms
- dashboards

## Container Insights

CloudWatch Container Insights collects, aggregates, and summarizes metrics and logs from containerized workloads. It supports EKS and can show cluster, node, pod, namespace, and service-level data.

Typical questions it helps answer:

- Which pod is using too much CPU?
- Which namespace uses the most memory?
- Which nodes are under pressure?
- Which pods are restarting?
- Which services have too few running pods?
- Is node filesystem filling up?

Common Container Insights metrics:

- `node_cpu_utilization`
- `node_memory_utilization`
- `node_filesystem_utilization`
- `node_number_of_running_pods`
- `pod_cpu_utilization`
- `pod_memory_utilization`
- `pod_number_of_container_restarts`
- `service_number_of_running_pods`

Interview line:

"Container Insights gives cluster-level and workload-level visibility without me manually building every metric pipeline from scratch."

## Installing CloudWatch Observability Add-on

Modern EKS setups can use the Amazon CloudWatch Observability EKS add-on.

Example:

```bash
aws eks create-addon \
  --region us-east-1 \
  --cluster-name interview-eks \
  --addon-name amazon-cloudwatch-observability
```

Check:

```bash
aws eks describe-addon \
  --region us-east-1 \
  --cluster-name interview-eks \
  --addon-name amazon-cloudwatch-observability

kubectl get pods -n amazon-cloudwatch
kubectl get amazoncloudwatchagent -A
```

What it installs:

- CloudWatch agent components
- CRDs/custom resources for agent configuration
- log/metric collection pieces depending on configuration

Failure scenarios:

- IAM permissions missing
- add-on conflict with existing CloudWatch agent
- nodes cannot reach CloudWatch APIs
- too much log ingestion cost
- agent pods pending due resource constraints

## Kubernetes Control Plane Logging

EKS can send control plane logs to CloudWatch Logs.

Types:

- API server
- audit
- authenticator
- controller manager
- scheduler

Enable:

```bash
aws eks update-cluster-config \
  --region us-east-1 \
  --name interview-eks \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

Why useful:

- audit who did what
- debug authentication problems
- inspect API server errors
- trace controller/scheduler issues

Cost caution:

Audit logs can be noisy and expensive. In production, decide retention and filters deliberately.

## CloudWatch Logs

Application logs commonly go to CloudWatch Logs through:

- CloudWatch agent
- Fluent Bit
- AWS for Fluent Bit
- ADOT Collector
- OpenTelemetry Collector

Best practices:

- log to stdout/stderr from containers
- use structured JSON logs
- include request id, trace id, user id when safe, service name, version, environment
- avoid logging secrets
- set log retention
- avoid debug-level logs in production by default

Useful CloudWatch Logs Insights examples:

Find errors:

```sql
fields @timestamp, @message
| filter @message like /ERROR|Exception|Traceback/
| sort @timestamp desc
| limit 50
```

Count errors by pod:

```sql
fields kubernetes.pod_name, @message
| filter @message like /ERROR/
| stats count(*) by kubernetes.pod_name
```

Latency from JSON logs:

```sql
fields @timestamp, path, status, latency_ms
| filter latency_ms > 1000
| sort latency_ms desc
| limit 50
```

Interview line:

"I prefer structured logs because they make incident queries fast and reliable."

## CloudWatch Alarms

Alarms turn metrics into action.

Common EKS alarms:

- high node CPU
- high node memory
- high node filesystem usage
- high pod restart count
- low healthy ALB target count
- high HTTP 5xx
- high p95 latency
- HPA max replicas reached
- pending pods for too long
- EBS volume burst balance or high queue length

Good alarm design:

- alert on symptoms users feel
- create tickets for early warnings
- avoid paging for noisy low-signal metrics
- include runbook links
- include dashboard links

Bad alarm design:

- alert on every single pod restart
- alert on transient CPU spikes
- no severity levels
- no owner
- no action text

## Prometheus And Grafana

CloudWatch is AWS-native. Prometheus is Kubernetes-native.

Prometheus is strong for:

- Kubernetes metrics
- application metrics
- PromQL
- service-level dashboards
- alert rules
- ecosystem integrations

Grafana is strong for:

- visual dashboards
- combining Prometheus, CloudWatch, Loki, Elasticsearch, and other sources
- SRE-style views

AWS managed options:

- Amazon Managed Service for Prometheus
- Amazon Managed Grafana

Production architecture:

```text
pods expose /metrics
-> Prometheus scraper or AWS managed collector
-> Amazon Managed Service for Prometheus
-> Grafana dashboards and alerts
```

Interview line:

"CloudWatch is great for AWS-native metrics and logs. Prometheus is common for Kubernetes and application metrics. Many companies use both."

## OpenTelemetry And Tracing

OpenTelemetry is a vendor-neutral standard for telemetry.

It can collect:

- traces
- metrics
- logs

Typical flow:

```text
application instrumentation
-> OpenTelemetry SDK
-> ADOT/OpenTelemetry Collector
-> X-Ray, Prometheus, CloudWatch, or another backend
```

AWS services to know:

- AWS Distro for OpenTelemetry
- AWS X-Ray
- CloudWatch Application Signals

When traces help:

- request latency across microservices
- dependency bottlenecks
- retry storms
- partial failures
- tail latency investigations

## AWS Load Balancer Observability

For ALB-backed EKS apps, watch:

- `HTTPCode_ELB_5XX_Count`
- `HTTPCode_Target_5XX_Count`
- `TargetResponseTime`
- `HealthyHostCount`
- `UnHealthyHostCount`
- `RequestCount`
- target group health

Important distinction:

- ELB 5xx often means load balancer-level issue
- Target 5xx means backend app returned error
- no healthy targets often means readiness, Service endpoints, or pod health problem

Debug path:

```bash
kubectl get ingress -n <ns>
kubectl describe ingress <name> -n <ns>
kubectl get svc,endpoints,endpointslice -n <ns>
kubectl get targetgroupbinding -n <ns>
```

## Real-Time Operational Activity

Day-2 operations are the repeated activities after the app is live.

Daily/weekly tasks:

- check dashboards
- review alerts
- inspect failed deployments
- review high-cost namespaces
- check cluster/node health
- review pending pods and restarts
- check vulnerability scans
- review IAM access changes
- review backup status
- apply security patches
- rotate secrets
- test restore process

During deployment:

- watch rollout status
- check app logs
- check ALB 5xx and latency
- check HPA behavior
- check error budget burn
- verify smoke endpoints
- confirm canary metrics before promotion

During incident:

```text
acknowledge alert
-> assess blast radius
-> identify recent changes
-> mitigate first
-> communicate status
-> find root cause
-> add prevention
-> write postmortem
```

Interview line:

"In an incident, I separate mitigation from root-cause analysis. First restore service, then investigate deeply."

## SLI, SLO, SLA

### SLI

Service Level Indicator. A measured signal.

Examples:

- request success rate
- p95 latency
- availability
- error rate

### SLO

Service Level Objective. Internal target.

Example:

```text
99.9 percent successful requests over 30 days
```

### SLA

Service Level Agreement. External contractual promise.

Interview line:

"Alerts should be tied to user-impacting SLIs, not just infrastructure noise."

## Golden Signals

For web services, watch:

- latency
- traffic
- errors
- saturation

Kubernetes-specific saturation:

- CPU requests vs usage
- memory working set
- node allocatable pressure
- pod density
- disk pressure
- HPA at max replicas
- queue depth

## Cost Optimization In EKS

Cost optimization is not just "use smaller instances." It means matching resources to actual workload requirements without hurting reliability.

Major cost drivers:

- EKS control plane hourly cost
- EC2 worker nodes
- EBS volumes and snapshots
- ALB/NLB hourly and LCU usage
- NAT Gateway hourly and data processing
- cross-AZ data transfer
- CloudWatch logs and custom metrics
- Amazon Managed Prometheus ingestion/query/storage
- Secrets Manager monthly secret cost
- Route 53 hosted zones

## Compute Cost Optimization

### Rightsize Requests And Limits

Requests drive scheduling and HPA math.

Bad requests cause:

- poor bin packing
- wasted nodes
- HPA over-scaling
- HPA under-scaling

Use:

```bash
kubectl top pods -A
kubectl top nodes
kubectl describe node <node>
```

Tools:

- VPA in recommendation mode
- Kubecost
- CloudWatch Container Insights
- Prometheus metrics

### Use HPA

HPA scales replicas based on metrics.

Good for:

- stateless web apps
- CPU-bound workers
- request-rate-driven workloads with custom metrics

Not enough for:

- node scaling by itself
- stateful apps without careful design
- workloads bottlenecked on database latency

### Use Cluster Autoscaler Or Karpenter

HPA adds pods. Cluster Autoscaler or Karpenter adds nodes.

Cluster Autoscaler:

- works with Auto Scaling Groups
- conservative
- familiar

Karpenter:

- provisions right-sized nodes dynamically
- good bin packing
- faster and flexible
- strong for mixed workloads

Interview line:

"HPA scales pods, Cluster Autoscaler or Karpenter scales nodes, and VPA recommends or changes resource requests."

### Use Spot Carefully

Good for:

- stateless workloads
- batch jobs
- dev/test clusters
- fault-tolerant workers

Be careful with:

- databases
- single-replica critical workloads
- workloads without PDBs
- workloads without graceful shutdown

Needed:

- multiple instance types
- multiple AZs
- PDBs
- graceful termination
- interruption handling

## Networking Cost Optimization

### NAT Gateway

NAT Gateway can be expensive because it has hourly and data processing charges.

Ways to reduce:

- use VPC endpoints for AWS APIs like ECR, S3, CloudWatch, STS, Secrets Manager
- avoid unnecessary private-to-public egress
- use private endpoints where possible
- avoid routing all logs/metrics inefficiently through NAT

### Cross-AZ Data Transfer

Cross-AZ traffic can cost money.

Example:

```text
app pod in AZ A
-> Redis/EBS-backed pod in AZ B
```

How to reduce:

- topology spread with awareness
- keep chatty dependencies close
- use multi-AZ services deliberately
- understand load balancer cross-zone behavior

### Load Balancers

Each ALB/NLB has cost.

Reduce by:

- sharing ALB with Ingress groups where appropriate
- deleting stale Ingress resources
- avoiding one ALB per tiny internal service unless needed
- checking target groups after app deletion

## Storage Cost Optimization

Watch:

- unattached EBS volumes
- old snapshots
- oversized PVCs
- high-performance volumes where gp3 is enough
- PV reclaim policy

Commands:

```bash
kubectl get pvc,pv -A
aws ec2 describe-volumes --region <region>
aws ec2 describe-snapshots --owner-ids self --region <region>
```

Kubernetes risk:

If StorageClass uses reclaim policy `Retain`, deleting PVC may leave cloud volumes behind.

## Observability Cost Optimization

CloudWatch and Prometheus costs can grow quickly.

Watch:

- log ingestion volume
- log retention
- custom metrics count
- high-cardinality metrics
- Prometheus scrape interval
- labels with user IDs/request IDs
- debug logs left enabled

Best practices:

- set retention for log groups
- sample noisy logs
- avoid high-cardinality labels
- avoid scraping too frequently without reason
- create dashboards for cost signals
- alert on sudden ingestion spikes

High-cardinality example:

Bad metric label:

```text
http_requests_total{user_id="123456", request_id="abc"}
```

Good metric labels:

```text
http_requests_total{service="api", route="/orders", status="200"}
```

## Cost Visibility Tools

AWS-native:

- AWS Cost Explorer
- AWS Budgets
- AWS Cost Anomaly Detection
- Cost and Usage Report
- tags and cost allocation tags

Kubernetes-specific:

- Kubecost
- OpenCost

Kubecost can break down cost by:

- namespace
- deployment
- service
- pod
- label
- team

Interview line:

"For Kubernetes cost, cloud bill alone is not enough. I need allocation by namespace, workload, and team."

## Security Services Worth Knowing

These are not all required for the lab, but knowing them helps in interviews.

### CloudTrail

Records AWS API activity.

Use it to answer:

- who deleted the load balancer?
- who changed IAM?
- who updated the cluster?
- which role assumed which permissions?

### AWS Config

Tracks resource configuration and compliance.

Use it for:

- auditing security group changes
- checking public resources
- compliance rules

### GuardDuty

Threat detection service.

Useful for:

- suspicious IAM activity
- unusual network behavior
- compromised credentials signals

### Security Hub

Aggregates security findings from AWS services.

### IAM Access Analyzer

Finds risky external access and validates IAM policies.

### Amazon Inspector

Vulnerability scanning for workloads and container images.

### ECR Scanning

Scans container images for vulnerabilities.

In pipeline:

```text
build image
-> scan image
-> block deploy on critical vulnerabilities
```

## Operations Services Worth Knowing

### EventBridge

Event routing.

Examples:

- trigger workflow when ECR image scan completes
- react to AWS Health events
- notify on scheduled maintenance

### SNS

Pub/sub notifications.

Examples:

- alarm notifications
- incident notifications

### SQS

Queue service.

Examples:

- async work
- decouple services
- retry failed jobs

### Lambda

Serverless compute.

Examples:

- cleanup stale resources
- process events
- small automation tasks

### Systems Manager

Operations toolkit.

Examples:

- Session Manager instead of SSH
- Parameter Store
- patching
- automation documents

### AWS Backup

Centralized backup service.

Use for:

- EBS snapshots
- RDS backups
- backup policies

## Dashboards To Build

### Cluster Health Dashboard

Panels:

- node CPU/memory
- node disk
- pod count per node
- pending pods
- pod restarts
- namespace resource usage
- HPA desired/current replicas

### Application Dashboard

Panels:

- request rate
- p95/p99 latency
- HTTP 4xx/5xx
- pod restarts
- deployment version
- Redis latency/errors
- dependency failures

### Cost Dashboard

Panels:

- daily AWS spend
- spend by service
- spend by namespace/team
- CloudWatch log ingestion
- NAT data processing
- unattached EBS volumes
- idle load balancers

## Alert Examples

Page-worthy:

- app success rate below SLO
- p95 latency above SLO for sustained window
- ALB has zero healthy targets
- many pods pending for more than 10 minutes
- node NotReady
- database unavailable

Ticket-worthy:

- CPU consistently high
- namespace nearing quota
- HPA frequently maxed
- disk usage growing
- log ingestion spike
- pod restart trend increasing

## Real Interview Scenario Answers

### "How do you monitor EKS?"

"I use a combination of CloudWatch Container Insights for cluster and pod metrics, CloudWatch Logs or Fluent Bit for logs, Prometheus for Kubernetes and app metrics, Grafana for dashboards, and tracing through OpenTelemetry or X-Ray for distributed requests. I alert on user-impacting SLIs like error rate and latency, plus platform risks like pending pods, node pressure, and zero healthy ALB targets."

### "How do you reduce EKS cost?"

"First I identify cost drivers with Cost Explorer, Kubecost, and metrics. Then I rightsize pod requests, improve bin packing, use HPA plus Cluster Autoscaler or Karpenter, use Spot where safe, reduce NAT and cross-AZ traffic, clean unused EBS volumes and load balancers, set log retention, control metric cardinality, and add budgets/anomaly alerts."

### "What do you do during an incident?"

"I acknowledge the alert, identify user impact, check recent deployments, follow the traffic path from DNS and ALB to Service endpoints and pods, mitigate first through rollback or scaling, then investigate root cause with logs, metrics, events, traces, and AWS audit data. After recovery, I document the incident and add prevention."

### "CloudWatch vs Prometheus?"

"CloudWatch is AWS-native and integrates well with AWS service metrics, logs, alarms, and dashboards. Prometheus is Kubernetes-native and strong for app and cluster metrics with PromQL. In real EKS platforms, both often coexist."

### "How do you avoid observability becoming expensive?"

"I set log retention, avoid debug logs in production, reduce noisy logs, avoid high-cardinality metrics, tune scrape intervals, monitor ingestion volume, and review dashboards/alerts for signal quality."

## Practical Commands

CloudWatch log groups:

```bash
aws logs describe-log-groups --region us-east-1
aws logs put-retention-policy --log-group-name <name> --retention-in-days 7
```

EKS add-on:

```bash
aws eks describe-addon --cluster-name <cluster> --addon-name amazon-cloudwatch-observability
```

Kubernetes quick checks:

```bash
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
kubectl top nodes
kubectl top pods -A
kubectl get hpa,pdb -A
```

Cost cleanup checks:

```bash
aws elbv2 describe-load-balancers --region us-east-1
aws ec2 describe-volumes --region us-east-1
aws ec2 describe-snapshots --owner-ids self --region us-east-1
aws ecr describe-repositories --region us-east-1
aws secretsmanager list-secrets --region us-east-1
aws route53 list-hosted-zones
```

## Final Mental Model

A strong EKS operator thinks in four loops:

```text
Reliability loop: detect, mitigate, recover, prevent
Deployment loop: build, scan, deploy, verify, rollback
Cost loop: measure, allocate, optimize, alert
Security loop: least privilege, audit, patch, scan, rotate
```

If you can explain these four loops with examples from our lab, you will sound much more production-ready than someone who only knows Kubernetes object definitions.

## Sources

- AWS CloudWatch Container Insights: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html
- CloudWatch Container Insights for EKS: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-EKS.html
- EKS Container Insights metrics: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html
- Amazon EKS cost optimization best practices: https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt.html
- EKS cost optimization framework: https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt-framework.html
- EKS cost optimization networking: https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt-networking.html
- Amazon Managed Service for Prometheus: https://docs.aws.amazon.com/prometheus/
- Amazon EKS Prometheus monitoring: https://docs.aws.amazon.com/eks/latest/userguide/prometheus.html
- Amazon EKS Kubecost support: https://docs.aws.amazon.com/eks/latest/userguide/cost-monitoring-kubecost-bundles.html

