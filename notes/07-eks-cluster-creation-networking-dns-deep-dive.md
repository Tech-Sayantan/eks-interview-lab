# EKS Cluster Creation, Networking, DNS, And AWS Resource Deep Dive

This note explains how our cluster was created, what AWS resources were involved, why each piece exists, and how to troubleshoot it.

## Big Picture

An EKS application exposed on a custom domain needs more than Kubernetes manifests.

The full path is:

```text
Browser
-> Route 53 DNS
-> ACM certificate for HTTPS
-> AWS Application Load Balancer
-> AWS Load Balancer Controller
-> Kubernetes Ingress
-> Kubernetes Service
-> Ready Pods
-> Redis StatefulSet / AWS APIs through IRSA
```

EKS itself has two large halves:

- AWS-managed control plane
- worker nodes where pods actually run

## Cluster Creation With eksctl

We used `eksctl` instead of Terraform for this practice.

The cluster script:

```bash
AWS_PROFILE=eks-lab AWS_REGION=us-east-1 \
CLUSTER_NAME=interview-eks K8S_VERSION=1.34 \
bash infra/scripts/02-create-cluster.sh
```

The script rendered:

```text
infra/eksctl/cluster-template.yaml
-> .generated/cluster.yaml
-> eksctl create cluster -f .generated/cluster.yaml
```

Important config from the template:

```yaml
metadata:
  name: interview-eks
  region: us-east-1

iam:
  withOIDC: true

vpc:
  cidr: 10.20.0.0/16
  nat:
    gateway: Disable
  clusterEndpoints:
    publicAccess: true
    privateAccess: false

nodeGroups:
  - name: ng-self-spot
    minSize: 1
    desiredCapacity: 2
    maxSize: 3
    privateNetworking: false
    instancesDistribution:
      onDemandPercentageAboveBaseCapacity: 0
```

## Why We Used This Shape

### `iam.withOIDC: true`

This creates the OIDC provider needed for IRSA.

IRSA means:

```text
Kubernetes ServiceAccount
-> projected web identity token
-> AWS STS AssumeRoleWithWebIdentity
-> temporary IAM credentials inside pod
```

Why it matters:

- no AWS keys inside Kubernetes secrets
- each app can get its own AWS permissions
- better than giving broad permissions to node IAM role

### Public Nodes And No NAT

We disabled NAT Gateway for cost:

```yaml
nat:
  gateway: Disable
privateNetworking: false
```

This means worker nodes live in public subnets and can reach the internet directly.

Production note:

In many real companies, nodes are in private subnets and egress goes through NAT Gateway, NAT instance, VPC endpoints, or controlled egress proxy. NAT Gateway costs money, so we skipped it for the lab.

Interview line:

"For a cost-sensitive lab, public worker nodes avoid NAT cost. For production, private nodes are usually preferred with controlled egress."

### Self-Managed Spot Node Group

We used a self-managed node group with Spot instances.

Why:

- cheaper
- good for practice
- lets us talk about node groups, EC2, ASG, and drain behavior

Risk:

- Spot can disappear
- small instance types have tight pod density limits
- self-managed means more responsibility than managed node groups

Production note:

Many teams prefer managed node groups or Karpenter. Karpenter is common for dynamic provisioning and consolidation.

## What eksctl Creates In AWS

`eksctl create cluster` typically creates CloudFormation stacks.

Major resources:

- EKS control plane
- IAM roles for cluster and nodes
- VPC
- public subnets across AZs
- route tables
- internet gateway
- security groups
- node group Auto Scaling Group
- EC2 worker nodes
- launch template or launch configuration
- node root EBS volumes

## VPC Concepts

### VPC

A VPC is your private network boundary in AWS.

Our CIDR:

```text
10.20.0.0/16
```

That gives the cluster a private IP range for subnets and nodes.

### Subnets

Subnets are AZ-scoped network segments inside the VPC.

EKS needs subnets so:

- nodes can run in multiple AZs
- load balancers can be created across AZs
- pods receive IPs from the VPC CNI

### Internet Gateway

An Internet Gateway lets public subnets route to/from the internet.

Route table pattern for public subnet:

```text
0.0.0.0/0 -> Internet Gateway
```

### NAT Gateway

NAT Gateway lets private subnet instances reach the internet without being publicly reachable.

We disabled it for cost.

Production tradeoff:

- NAT Gateway is managed and reliable but costs money
- VPC endpoints reduce NAT traffic for AWS APIs
- private subnets improve network exposure posture

### Route Tables

Route tables decide where packets go.

Common routes:

```text
local VPC CIDR -> local
0.0.0.0/0 -> Internet Gateway
0.0.0.0/0 -> NAT Gateway
```

### NACL

Network ACLs are stateless subnet-level firewall rules.

Important:

- NACL is stateless
- Security Group is stateful
- NACL applies at subnet boundary
- SG applies to ENI/instance/load balancer level

Interview line:

"Security Groups are stateful and attached to ENIs; NACLs are stateless and attached to subnets."

### Security Groups

Security Groups controlled traffic for:

- EKS control plane to nodes
- nodes to control plane
- ALB to pod/node targets
- node-to-node traffic

With AWS Load Balancer Controller target type `ip`, ALB can target pod IPs directly.

## EKS Control Plane

AWS manages:

- Kubernetes API server
- etcd
- control plane availability
- control plane upgrades

You manage:

- worker nodes
- add-ons
- workloads
- IAM access
- network policies
- cost

Important command:

```bash
aws eks update-kubeconfig --region us-east-1 --name interview-eks --profile eks-lab
```

This updates local kubeconfig so `kubectl` can talk to the EKS API server.

## Node Group

The node group is a set of EC2 instances that join the cluster as Kubernetes nodes.

Each node runs:

- kubelet
- container runtime
- kube-proxy
- VPC CNI daemon
- EBS CSI node plugin
- your pods

Useful commands:

```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
kubectl get nodes -L topology.kubernetes.io/zone
```

Things to inspect:

- node readiness
- taints
- labels
- allocatable CPU/memory
- max pod capacity
- running pods
- AZ labels

## VPC CNI

EKS commonly uses the Amazon VPC CNI.

Key idea:

Pods get VPC IP addresses. This is different from overlay networks where pod IPs live in a separate virtual network.

Benefits:

- AWS-native networking
- pod IPs are routable in VPC
- works naturally with AWS load balancers

Common issue:

Small instances have limited ENI/IP capacity, which can limit pod count.

We saw a related practical issue:

- `t3.small` nodes allowed only a small number of pods
- the `us-east-1d` node became full by pod count
- Redis could not schedule even though CPU/memory looked okay

## Add-ons We Installed

### VPC CNI NetworkPolicy Support

Script:

```bash
aws eks update-addon \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name vpc-cni \
  --resolve-conflicts OVERWRITE \
  --configuration-values '{"enableNetworkPolicy":"true","nodeAgent":{"healthProbeBindAddr":"8163","metricsBindAddr":"8162"}}'
```

Why:

To practice Kubernetes NetworkPolicy enforcement on EKS.

### metrics-server

Installed from upstream manifest.

Why:

- enables `kubectl top`
- enables HPA CPU/memory metrics

Troubleshooting:

```bash
kubectl get deployment metrics-server -n kube-system
kubectl top pods -n interview
kubectl describe hpa interview-app -n interview
```

### EBS CSI Driver

Installed as EKS add-on with IRSA.

Why:

Kubernetes no longer relies on the old in-tree AWS EBS volume plugin. EBS CSI provisions and attaches EBS volumes for PVCs.

Key objects:

- StorageClass
- PVC
- PV
- VolumeAttachment
- EBS volume in AWS

### AWS Load Balancer Controller

Installed with Helm and IRSA.

Why:

It watches Kubernetes Ingress resources and creates AWS ALBs, listeners, rules, target groups, and target group bindings.

Important concept:

Kubernetes Ingress is desired state. The AWS Load Balancer Controller converts that desired state into AWS resources.

## DNS And ACM Flow

### Route 53 Hosted Zone

We used hosted zone:

```text
tanscape.online
```

If the hosted zone did not exist, the script would create it.

Then GoDaddy nameservers must point to Route 53 nameservers.

### ACM Certificate

We requested an ACM certificate for:

```text
app.tanscape.online
```

ACM validation used DNS:

```text
ACM gives CNAME validation record
-> script creates CNAME in Route 53
-> ACM sees validation
-> certificate becomes ISSUED
```

Important:

For ALB in `us-east-1`, the ACM certificate must also be in `us-east-1`.

### Route 53 Alias To ALB

After the Ingress created an ALB, we created an alias:

```text
app.tanscape.online -> ALB DNS name
```

Script:

```bash
bash infra/scripts/07-route53-alias.sh
```

Alias records are better than CNAME at zone apex and integrate with AWS load balancer hosted zone IDs.

## App Deployment Flow

Manual deployment path:

```text
docker build
-> docker push to ECR
-> helm upgrade --install
-> Deployment rolls pods
-> Service endpoints update
-> ALB target groups see healthy pods
```

GitHub Actions path:

```text
push to main
-> GitHub OIDC assumes AWS role
-> build image
-> push ECR tag using git SHA
-> update kubeconfig
-> helm lint
-> helm upgrade --install
```

## Troubleshooting Cluster Creation

### EKS Cluster Creation Fails

Check:

```bash
eksctl utils describe-stacks --cluster interview-eks --region us-east-1
aws cloudformation describe-stack-events --stack-name <stack-name> --region us-east-1
```

Likely causes:

- IAM permission missing
- subnet/VPC limit
- EC2 capacity unavailable
- unsupported Kubernetes version
- service quota exceeded

### Nodes Not Joining

Check:

```bash
kubectl get nodes
aws autoscaling describe-auto-scaling-groups --region us-east-1
aws ec2 describe-instances --region us-east-1
```

Likely causes:

- node IAM role issue
- bootstrap failure
- security group issue
- no route to control plane
- AMI problem

### ALB Not Created

Check:

```bash
kubectl describe ingress interview-app -n interview
kubectl logs -n kube-system deployment/aws-load-balancer-controller
kubectl get targetgroupbinding -n interview
```

Likely causes:

- controller not running
- missing IAM permissions
- subnet tags missing
- bad Ingress annotation
- certificate ARN wrong

### Domain Does Not Resolve

Check:

```bash
dig app.tanscape.online
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

Likely causes:

- GoDaddy nameservers not updated
- Route 53 alias missing
- DNS propagation delay
- wrong hosted zone

## Cost Notes

Major costs:

- EKS control plane hourly charge
- EC2 worker nodes
- EBS volumes
- ALB hourly and LCU charges
- NAT Gateway if enabled
- Route 53 hosted zone
- Secrets Manager secret monthly charge
- ECR storage

We reduced cost by:

- using Spot nodes
- disabling NAT Gateway
- using small nodes
- tearing down after practice

But the small nodes caused a real pod-density scheduling issue. Cheap labs produce excellent lessons.

