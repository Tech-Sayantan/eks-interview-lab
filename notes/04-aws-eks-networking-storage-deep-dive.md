# 04 - AWS, EKS, Networking, Storage, And Secrets Deep Dive

This chapter explains the AWS side of the lab: what was created, when it was created, why it exists, and how to answer interview questions around EKS networking, node groups, EBS, IAM, ALB, Route 53, ACM, and Secrets Manager.

## 1. What We Actually Created

High-level AWS inventory:

```text
Route 53 hosted zone: tanscape.online
ACM certificate: app.tanscape.online
EKS cluster: interview-eks
VPC: created by eksctl
Subnets: created by eksctl
Internet Gateway: created by eksctl
Route tables: created by eksctl
Security groups: created by eksctl and controllers
Self-managed node group: ng-self-spot
EC2 worker nodes: Spot instances
EBS volumes: node root disks and Redis PVC volume
ECR repository: interview-app
ALB: created by AWS Load Balancer Controller
S3 bucket: IRSA demo bucket
IAM roles: nodes, add-ons, app IRSA, GitHub Actions OIDC
CloudFormation stacks: created by eksctl
```

Important mental model:

```text
eksctl create cluster
  -> creates CloudFormation stacks
  -> CloudFormation creates VPC/network/IAM/EKS/node resources
  -> EC2 nodes bootstrap and join EKS
  -> kubectl sees nodes
```

## 2. The Cluster Config We Used

File:

```text
infra/eksctl/cluster-template.yaml
```

Key parts:

```yaml
metadata:
  name: interview-eks
  region: us-east-1
  version: "1.34"

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
    amiFamily: AmazonLinux2023
    volumeSize: 30
    volumeType: gp3
    privateNetworking: false
    ssh:
      allow: false
    instancesDistribution:
      instanceTypes:
        - t3.small
        - t3a.small
        - t3.medium
        - t3a.medium
      onDemandBaseCapacity: 0
      onDemandPercentageAboveBaseCapacity: 0
      spotAllocationStrategy: capacity-optimized
```

Interview summary:

> We used eksctl to create an EKS cluster in us-east-1 with OIDC enabled, a new VPC CIDR 10.20.0.0/16, public cluster endpoint, no NAT Gateway for cost control, and a self-managed Spot node group using Amazon Linux 2023 EC2 instances.

## 3. When Did VPC, Subnets, And Node Group Get Created?

They were created during:

```bash
infra/scripts/02-create-cluster.sh
```

That script rendered the eksctl template and ran:

```bash
eksctl create cluster -f .generated/cluster.yaml
```

Because we did not specify an existing VPC/subnet IDs, eksctl created a fresh VPC for us.

Creation sequence conceptually:

1. Create VPC.
2. Create subnets across Availability Zones.
3. Create internet gateway and route tables.
4. Create EKS control plane.
5. Create IAM roles and security groups.
6. Create node group infrastructure.
7. Launch EC2 nodes.
8. Bootstrap nodes into the Kubernetes cluster.
9. Save kubeconfig.

Commands to inspect:

```bash
aws cloudformation list-stacks \
  --profile eks-lab \
  --region us-east-1 \
  --query "StackSummaries[?contains(StackName, 'eksctl-interview-eks')].[StackName,StackStatus]" \
  --output table

aws eks describe-cluster \
  --profile eks-lab \
  --region us-east-1 \
  --name interview-eks \
  --query "cluster.resourcesVpcConfig"

kubectl get nodes -o wide
```

## 4. What Is A Node Group?

A node group is a group of worker machines that join the EKS cluster.

Kubernetes control plane needs worker nodes to run pods. In EKS:

- AWS manages the control plane.
- Worker nodes run in your AWS account.
- Pods run on worker nodes.

Our node group:

```text
Name: ng-self-spot
Type: self-managed node group
Desired nodes: 2
Minimum nodes: 1
Maximum nodes: 3
Capacity: Spot
OS/AMI family: Amazon Linux 2023
Instance types: t3.small, t3a.small, t3.medium, t3a.medium
Root volume: 30 GiB gp3
```

Self-managed node group means:

- EC2 instances are usually managed through an Auto Scaling Group and CloudFormation.
- You are more responsible for upgrades, AMI lifecycle, draining, and replacement.
- It gives flexibility but more operational work.

Managed node group means:

- AWS EKS manages more of the lifecycle.
- Easier upgrades and repairs.
- Still runs EC2 nodes in your account.

Fargate means:

- No EC2 node management for supported pods.
- Different tradeoffs and limitations.

Interview line:

> A node group is the compute layer for Kubernetes pods. EKS manages the control plane, but node groups provide worker capacity.

## 5. Why Spot Nodes?

Spot instances are spare EC2 capacity at lower cost, but AWS can interrupt them.

Why we used Spot:

- Cheap for a short practice lab.
- Good interview topic.
- We are not running production traffic.

Production caveats:

- Use multiple instance types.
- Use capacity-optimized allocation.
- Handle interruptions.
- Use PodDisruptionBudget.
- Use multiple AZs.
- Use Cluster Autoscaler/Karpenter.
- Do not put critical single-replica stateful workloads only on Spot without a plan.

Our config:

```yaml
spotAllocationStrategy: capacity-optimized
instanceTypes:
  - t3.small
  - t3a.small
  - t3.medium
  - t3a.medium
```

Interview line:

> Spot is cost-effective but interruptible. For production, I combine diversification, graceful termination handling, PDBs, autoscaling, and avoid placing fragile stateful workloads only on Spot.

## 6. EKS Control Plane

What AWS manages:

- Kubernetes API server.
- etcd.
- Control plane availability.
- Control plane patching within AWS model.

What you still manage:

- Nodes.
- Add-ons.
- IAM.
- VPC/networking.
- Workload manifests.
- Autoscaling.
- Observability.
- Upgrades/version skew.

Public endpoint:

```yaml
clusterEndpoints:
  publicAccess: true
  privateAccess: false
```

Meaning:

- Kubernetes API server is reachable over the public internet, protected by authentication/authorization.
- Simpler for a lab.

Production alternative:

- Enable private endpoint.
- Restrict public endpoint CIDRs or disable public endpoint.
- Access through VPN, Direct Connect, bastion, SSM, or private networks.

Interview line:

> EKS removes the burden of running etcd and API servers, but it does not remove responsibility for networking, IAM, node lifecycle, and workload reliability.

## 7. VPC Deep Dive

VPC is the private network boundary in AWS.

Our VPC:

```yaml
vpc:
  cidr: 10.20.0.0/16
```

This gives private IP space from `10.20.0.0` to `10.20.255.255`.

Why VPC matters for EKS:

- Worker nodes live in subnets inside the VPC.
- Pods receive network connectivity through CNI.
- Load balancers are placed in subnets.
- Security groups control traffic.
- Route tables control network paths.

Inspect:

```bash
VPC_ID="$(aws eks describe-cluster \
  --profile eks-lab \
  --region us-east-1 \
  --name interview-eks \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)"

aws ec2 describe-vpcs \
  --profile eks-lab \
  --region us-east-1 \
  --vpc-ids "$VPC_ID" \
  --output table
```

## 8. Subnets

A subnet is an AZ-scoped slice of a VPC.

Important:

- VPC is regional.
- Subnet belongs to one Availability Zone.
- EC2 instances run in subnets.
- ALB needs at least two subnets across AZs for high availability.
- EBS volumes are AZ-scoped.

Public subnet:

- Route table has route to Internet Gateway.
- Resources can have public IPs.

Private subnet:

- No direct route to Internet Gateway.
- Outbound internet usually through NAT Gateway or VPC endpoints.

Our lab choice:

```yaml
nat:
  gateway: Disable
privateNetworking: false
```

Meaning:

- We avoided NAT Gateway to reduce cost.
- Worker nodes were placed in public networking mode.

Production answer:

> For production, I usually put worker nodes in private subnets and use NAT Gateway or VPC endpoints for outbound access to AWS services. Public nodes are acceptable for a short lab but not my default production design.

Inspect:

```bash
aws ec2 describe-subnets \
  --profile eks-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch]" \
  --output table
```

## 9. Internet Gateway

Internet Gateway, or IGW, gives VPC resources a path to/from the internet when route tables allow it.

Public subnet route usually has:

```text
0.0.0.0/0 -> igw-xxxx
```

Meaning:

- Traffic not matching local VPC routes goes to the internet gateway.

Why our lab needs it:

- Public ALB must be reachable from internet.
- Public worker nodes need outbound access without NAT.
- We avoided NAT Gateway cost.

Inspect:

```bash
aws ec2 describe-internet-gateways \
  --profile eks-lab \
  --region us-east-1 \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --output table
```

## 10. Route Tables

Route table decides where packets go.

Common routes:

```text
10.20.0.0/16 -> local
0.0.0.0/0   -> internet gateway, NAT gateway, or other target
```

Public route table:

```text
0.0.0.0/0 -> IGW
```

Private route table:

```text
0.0.0.0/0 -> NAT Gateway
```

Our lab:

- Public-style networking because NAT disabled and nodes not private.

Inspect:

```bash
aws ec2 describe-route-tables \
  --profile eks-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[*].[RouteTableId,Routes]" \
  --output json
```

## 11. NACL

NACL means Network Access Control List.

NACL properties:

- Subnet-level.
- Stateless.
- Ordered rules.
- Has allow and deny rules.
- Applies to all resources in associated subnet.

Security Group properties:

- ENI/resource-level.
- Stateful.
- Allow rules only.
- Return traffic automatically allowed.

Interview line:

> NACL is subnet-level and stateless; Security Group is resource-level and stateful.

Our lab:

- eksctl likely used default permissive NACL behavior unless customized.
- We did not manually tune NACLs because this is a short practice lab.

Production:

- Many teams keep NACLs broad and rely more on Security Groups.
- Some regulated environments use NACLs as an extra subnet-level boundary.

Inspect:

```bash
aws ec2 describe-network-acls \
  --profile eks-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --output table
```

## 12. Security Groups

Security Groups are virtual firewalls attached to ENIs.

In this lab, security groups exist for:

- EKS cluster/control plane communication.
- Worker nodes.
- ALB.
- Pod/target traffic managed by AWS Load Balancer Controller.

Important:

- Security Groups are stateful.
- If inbound traffic is allowed, response traffic is automatically allowed.
- They have allow rules, not deny rules.

What happened to EC2 worker node security:

- eksctl created node security groups.
- SSH was disabled:

```yaml
ssh:
  allow: false
```

- Nodes still need security group rules for cluster/node/pod communication.
- AWS Load Balancer Controller manages rules needed for ALB to reach pod targets.

Inspect:

```bash
aws ec2 describe-security-groups \
  --profile eks-lab \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[*].[GroupName,GroupId,Description]" \
  --output table
```

Interview line:

> Security Groups are stateful ENI-level controls. In EKS, there are security groups for the cluster, nodes, and load balancers, and controllers may manage rules dynamically.

## 13. NAT Gateway And Why We Disabled It

NAT Gateway lets private subnet resources reach the internet without being reachable from the internet.

Production:

```text
private node -> NAT Gateway -> internet
```

Lab:

```yaml
nat:
  gateway: Disable
```

Why:

- NAT Gateway can become one of the larger fixed costs in a short lab.
- We wanted to minimize cost.

Tradeoff:

- Nodes are public-networked in this lab.
- Not ideal production posture.

Interview answer:

> For cost-controlled practice I disabled NAT and used public nodes. In production, I would normally run nodes in private subnets and use NAT Gateway or VPC endpoints for outbound access.

## 14. VPC Endpoints

VPC endpoints let private resources reach AWS services without going through the public internet.

Useful endpoints for private EKS clusters:

- ECR API.
- ECR Docker.
- S3 gateway endpoint.
- CloudWatch Logs.
- STS.
- EC2.
- EKS.
 
Production benefit:

- Reduce NAT dependency.
- Improve private connectivity.
- More controlled network path.

Interview line:

> In private EKS environments, VPC endpoints are often used so nodes can pull ECR images, write logs, and call AWS APIs without public internet egress.

## 15. EBS Deep Dive

EBS means Elastic Block Store.

Think of EBS as a network-attached block disk for EC2.

Properties:

- AZ-scoped.
- Usually attached to one node at a time for normal Kubernetes usage.
- Good for low-latency block storage.
- Used by StatefulSets through PVC/PV.

Our EBS usage:

1. Worker node root volumes:

```yaml
volumeSize: 30
volumeType: gp3
```

2. Redis PVC volume:

```yaml
storageClassName: interview-gp3
resources:
  requests:
    storage: 2Gi
```

Storage flow:

```text
StatefulSet volumeClaimTemplates
  -> PVC data-interview-app-redis-0
  -> StorageClass interview-gp3
  -> EBS CSI driver
  -> AWS EBS volume
  -> PV
  -> mounted into Redis pod
```

Important EBS/Kubernetes terms:

- `StorageClass`: how to provision storage.
- `PVC`: workload's request for storage.
- `PV`: actual Kubernetes representation of backing storage.
- `EBS volume`: AWS disk behind the PV.

Why `ReadWriteOnce`:

EBS volumes are normally mounted read-write by one node at a time.

Why AZ matters:

If EBS volume is in `us-east-1a`, the pod using it must run on a node in `us-east-1a`.

Why `WaitForFirstConsumer`:

It delays volume creation until a pod is scheduled, avoiding wrong-AZ volume creation.

Inspect:

```bash
kubectl get storageclass
kubectl get pvc -n interview
kubectl get pv
kubectl describe pvc data-interview-app-redis-0 -n interview
aws ec2 describe-volumes \
  --profile eks-lab \
  --region us-east-1 \
  --filters "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=interview" \
  --output table
```

Interview line:

> EBS is block storage and AZ-scoped. Kubernetes uses EBS through the EBS CSI driver, StorageClass, PVC, and PV. For multi-AZ or shared filesystem use cases, EFS may be more appropriate.

## 16. EBS vs EFS vs S3

EBS:

- Block storage.
- Attached to EC2/node.
- AZ-scoped.
- Good for databases needing block device.
- Kubernetes PVC common with StatefulSet.

EFS:

- Managed NFS filesystem.
- Multi-AZ.
- Multiple pods/nodes can mount.
- Useful for shared filesystem workloads.

S3:

- Object storage.
- Not a mounted block filesystem by default.
- Great for objects, backups, static assets, logs, data lake style workloads.

Interview answer:

> For Redis/Postgres-style block storage I think EBS. For shared filesystem across pods/AZs I think EFS. For object storage and backups I think S3.

## 17. EBS CSI Driver

Why needed:

Kubernetes does not magically create AWS EBS volumes by itself. The EBS CSI driver integrates Kubernetes storage APIs with AWS EBS APIs.

Installed in:

```bash
infra/scripts/03-install-addons.sh
```

We created an IAM role:

```text
interview-eks-AmazonEKS_EBS_CSI_DriverRole
```

Attached AWS managed policy:

```text
AmazonEBSCSIDriverPolicy
```

Then installed EKS add-on:

```text
aws-ebs-csi-driver
```

Interview line:

> The CSI driver watches PVC/PV operations and calls AWS APIs to create, attach, mount, detach, and delete EBS volumes.

## 18. AWS Load Balancer Controller

Why needed:

Kubernetes Ingress is just an API object. It does not create an AWS ALB by itself.

AWS Load Balancer Controller watches:

- Ingress.
- Service annotations.
- TargetGroupBinding.

It creates/manages:

- ALB.
- Listeners.
- Listener rules.
- Target groups.
- Security group rules.
- Target registrations.

Installed in:

```bash
infra/scripts/03-install-addons.sh
```

With IAM role:

```text
interview-eks-AmazonEKSLoadBalancerControllerRole
```

Why ALB target type `ip`:

```yaml
alb.ingress.kubernetes.io/target-type: ip
```

This registers pod IPs as ALB targets. Good fit for EKS VPC CNI because pods have VPC-routable IPs.

Interview line:

> Ingress defines desired routing. AWS Load Balancer Controller reconciles it into real AWS ALB resources.

## 19. Route 53 And ACM

Route 53:

- Hosted zone for `tanscape.online`.
- Alias record for `app.tanscape.online`.
- Points to ALB DNS name.

ACM:

- Certificate for `app.tanscape.online`.
- Validated using DNS.
- Used by ALB HTTPS listener.

Important:

- ACM certificate for ALB must be in the same region as the ALB.
- Our ALB is in `us-east-1`, so cert is in `us-east-1`.

Traffic:

```text
https://app.tanscape.online
  -> Route 53 alias
  -> ALB
  -> HTTPS listener with ACM certificate
  -> target group
  -> pod IPs
```

## 20. ECR

ECR stores Docker images.

Manual flow:

```bash
aws ecr get-login-password --region us-east-1 --profile eks-lab \
  | docker login --username AWS --password-stdin 923988301700.dkr.ecr.us-east-1.amazonaws.com

docker build --platform linux/amd64 \
  -t 923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1 \
  app

docker push 923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1
```

CI/CD flow:

- GitHub Actions assumes AWS role through OIDC.
- Logs into ECR.
- Builds image.
- Tags image with commit SHA.
- Pushes image.
- Helm deploys that tag.

Interview line:

> ECR is the private container registry. Nodes pull images from ECR when Kubernetes schedules pods.

## 21. IAM And IRSA

IAM roles in this lab:

- Node role: lets EC2 nodes do required node-level AWS tasks.
- EBS CSI role: lets CSI create/attach/detach EBS volumes.
- Load Balancer Controller role: lets controller create/manage ALB resources.
- App IRSA role: lets app pod call limited AWS APIs.
- GitHub Actions role: lets CI/CD build, push, and deploy.

IRSA:

```text
Kubernetes ServiceAccount
  -> OIDC token
  -> AWS STS AssumeRoleWithWebIdentity
  -> temporary IAM credentials
```

GitHub Actions OIDC:

```text
GitHub workflow
  -> GitHub OIDC token
  -> AWS STS AssumeRoleWithWebIdentity
  -> temporary IAM credentials
```

Common root cause:

- The role exists, but trust policy `sub` does not match.

Interview line:

> IAM controls AWS API permissions. Kubernetes RBAC/access controls Kubernetes API permissions. For EKS CI/CD, both layers matter.

## 22. Can We Use AWS Secrets Manager?

Yes. There are three common patterns.

### Option A: App Reads Secrets Manager Directly

Flow:

```text
Pod -> IRSA role -> AWS Secrets Manager API -> app memory
```

Pros:

- No extra Kubernetes operator.
- Easy to understand.
- Good for small apps.

Cons:

- App code must know AWS Secrets Manager.
- Secret retrieval/caching/retry becomes app responsibility.
- Less portable across clouds.

Required:

- Create secret in AWS Secrets Manager.
- Add `secretsmanager:GetSecretValue` to app IRSA role.
- Add app code to call Secrets Manager.

Example IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:us-east-1:923988301700:secret:interview/app/demo-*"
    }
  ]
}
```

### Option B: External Secrets Operator

Flow:

```text
External Secrets Operator
  -> reads AWS Secrets Manager
  -> creates Kubernetes Secret
  -> app consumes Kubernetes Secret
```

Pros:

- App remains cloud-agnostic.
- Kubernetes-native workflow.
- Good production pattern.

Cons:

- More moving parts.
- Need CRDs/operator.
- Need operator IAM setup.

Objects:

- `SecretStore` or `ClusterSecretStore`.
- `ExternalSecret`.
- Kubernetes `Secret`.

Interview line:

> External Secrets Operator keeps app code simple by syncing cloud secrets into Kubernetes Secrets, but it adds an operator and CRDs to operate.

### Option C: Secrets Store CSI Driver With AWS Provider

Flow:

```text
Pod mounts CSI volume
  -> CSI provider pulls secret from Secrets Manager
  -> secret appears as file in pod
```

Pros:

- Secret can be mounted as file.
- Can avoid storing secret as Kubernetes Secret unless sync is enabled.

Cons:

- More add-ons.
- File-mounted secret requires app support or sidecar reload behavior.

Interview line:

> Secrets Store CSI Driver mounts external secrets into pods as volumes. External Secrets Operator syncs external secrets into Kubernetes Secrets. Direct SDK access puts responsibility in app code.

## 23. Which Secrets Manager Pattern Should We Use In This Lab?

For learning, I would do Option A first:

- Create one Secrets Manager secret.
- Give app IRSA permission.
- Add endpoint `/secret-manager-check`.
- Prove the app pod can read the secret through IRSA.

Why:

- No new cluster add-on.
- Reinforces IRSA.
- Easy to debug.

For production interview answer, say:

> I prefer External Secrets Operator or Secrets Store CSI Driver when platform teams want centralized secret management and app teams should consume Kubernetes-native Secrets or mounted files. For simple services, direct SDK access through IRSA is also valid.

## 24. Commands To Inspect The AWS Side

Set:

```bash
export AWS_PROFILE=eks-lab
export AWS_REGION=us-east-1
export CLUSTER_NAME=interview-eks
```

Cluster:

```bash
aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE"
```

VPC ID:

```bash
VPC_ID="$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)"
echo "$VPC_ID"
```

Subnets:

```bash
aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch]" \
  --output table
```

Route tables:

```bash
aws ec2 describe-route-tables \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --output table
```

Internet gateway:

```bash
aws ec2 describe-internet-gateways \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --output table
```

NACL:

```bash
aws ec2 describe-network-acls \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --output table
```

Security groups:

```bash
aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[*].[GroupName,GroupId,Description]" \
  --output table
```

EC2 nodes:

```bash
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
  --query "Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress,Placement.AvailabilityZone]" \
  --output table
```

Auto Scaling Groups:

```bash
aws autoscaling describe-auto-scaling-groups \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'ng-self-spot')].[AutoScalingGroupName,MinSize,DesiredCapacity,MaxSize]" \
  --output table
```

EBS volumes:

```bash
aws ec2 describe-volumes \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --filters "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=interview" \
  --output table
```

ALB:

```bash
aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --output table
```

ECR:

```bash
aws ecr describe-images \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --repository-name interview-app \
  --query "imageDetails[*].[imageTags,imagePushedAt]" \
  --output table
```

CloudFormation:

```bash
aws cloudformation list-stacks \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "StackSummaries[?contains(StackName, 'eksctl-interview-eks')].[StackName,StackStatus]" \
  --output table
```

## 25. Interview Story: How This Cluster Was Built

Use this:

> I used eksctl to create the EKS cluster from a ClusterConfig file. Since I did not pass an existing VPC, eksctl created a dedicated VPC with CIDR 10.20.0.0/16, subnets, route tables, internet gateway, security groups, and CloudFormation stacks. I enabled OIDC for IRSA. The compute layer is a self-managed Spot node group named ng-self-spot, desired size two, backed by EC2 Auto Scaling. For cost control I disabled NAT Gateway and used public node networking in the lab, though in production I would prefer private subnets with NAT or VPC endpoints. Then I installed add-ons: VPC CNI NetworkPolicy support, metrics-server, EBS CSI driver with IRSA, and AWS Load Balancer Controller with IRSA.

## 26. Interview Story: How Traffic Reaches The Pod

Use this:

> A user resolves app.tanscape.online in Route 53. The alias record points to an internet-facing ALB. The ALB uses an ACM certificate for HTTPS. AWS Load Balancer Controller created the ALB from the Kubernetes Ingress. The ALB target group points to pod IPs because target-type is ip. Traffic goes to the Kubernetes Service, then to ready app pods selected by labels. Readiness matters because unhealthy pods should not receive traffic.

## 27. Interview Story: How Redis Gets Persistent Storage

Use this:

> Redis runs as a StatefulSet with a volumeClaimTemplate. Kubernetes creates a PVC named data-interview-app-redis-0. That PVC uses the interview-gp3 StorageClass, whose provisioner is ebs.csi.aws.com. The EBS CSI driver calls AWS APIs to create an encrypted gp3 EBS volume. Kubernetes binds the PV to the PVC and mounts it into the Redis pod at /data. Since EBS is AZ-scoped and ReadWriteOnce, pod scheduling and volume AZ must align.

