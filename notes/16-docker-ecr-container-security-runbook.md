# Docker, ECR, Container Images, And Security Runbook

This note fills the Docker/container gap for the interview.

EKS interviews often start with Kubernetes, then suddenly ask:

```text
What happens when you build an image?
Why did ImagePullBackOff happen?
How do you reduce image size?
How do you secure containers?
What is the difference between CMD and ENTRYPOINT?
How does ECR fit into the pipeline?
```

## Core Mental Model

```text
source code
-> Dockerfile
-> image layers
-> image tag/digest
-> registry such as ECR
-> Kubernetes pulls image
-> container runtime starts container
-> app process runs as PID 1 inside container
```

Interview line:

"A Docker image is an immutable packaged artifact. A container is a running process created from that image with filesystem, network, and resource isolation."

## Image vs Container

Image:

- build-time artifact
- read-only layers
- stored in a registry
- versioned by tag and digest

Container:

- runtime instance of an image
- has writable layer
- has process namespace, network namespace, environment variables, mounted files
- should be disposable

Analogy:

```text
image = class
container = object instance
```

Do not overuse the analogy in interviews, but it helps memory.

## Dockerfile Basics

Typical good Dockerfile:

```Dockerfile
FROM python:3.12-slim

WORKDIR /app

RUN adduser --disabled-password --gecos "" app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src ./src

USER app

EXPOSE 8080

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

Important points:

- use a small base image
- avoid running as root
- copy dependency files before app code to improve layer cache
- use `.dockerignore`
- avoid baking secrets into images
- expose the right port
- use exec-form `CMD` so signals work properly

## Layers And Build Cache

Every Dockerfile instruction can create a layer.

Example:

```Dockerfile
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY src ./src
```

If only app code changes, Docker can reuse the dependency install layer.

Bad pattern:

```Dockerfile
COPY . .
RUN pip install -r requirements.txt
```

This invalidates dependency cache whenever any file changes.

Interview line:

"I structure Dockerfiles so slow dependency layers are cached unless dependency files change."

## `.dockerignore`

`.dockerignore` controls what enters the build context.

Common entries:

```text
.git
__pycache__
.venv
node_modules
.env
*.pem
*.key
*.csv
```

Why it matters:

- smaller build context
- faster builds
- avoids accidentally sending secrets to Docker daemon/build system
- prevents unnecessary cache invalidation

## CMD vs ENTRYPOINT

`CMD`:

- default command
- can be overridden easily

`ENTRYPOINT`:

- fixed executable contract
- arguments can be appended through `CMD`

Example:

```Dockerfile
ENTRYPOINT ["python", "-m", "myapp"]
CMD ["--port", "8080"]
```

Kubernetes equivalent:

```yaml
containers:
  - name: app
    image: example
    command: ["python", "-m", "myapp"]
    args: ["--port", "8080"]
```

Kubernetes `command` overrides Docker `ENTRYPOINT`.

Kubernetes `args` overrides Docker `CMD`.

## Tags vs Digests

Tag:

```text
interview-app:manual-v1
interview-app:latest
interview-app:abc123
```

Digest:

```text
sha256:...
```

Tags can move. Digests are immutable.

Production best practice:

- deploy immutable tags such as Git SHA
- for highest supply-chain safety, pin by digest
- avoid `latest` in Kubernetes deployments

Good:

```yaml
image: 923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:c7002ee
imagePullPolicy: IfNotPresent
```

For `latest`, Kubernetes defaults can surprise you.

## Multi-Stage Builds

Useful when build tools are not needed at runtime.

Example for Go:

```Dockerfile
FROM golang:1.23 AS build
WORKDIR /src
COPY . .
RUN go build -o /out/app ./cmd/app

FROM gcr.io/distroless/base-debian12
COPY --from=build /out/app /app
USER nonroot
ENTRYPOINT ["/app"]
```

Benefits:

- smaller runtime image
- fewer vulnerabilities
- faster pulls
- smaller attack surface

## Container Security Basics

Important controls:

- run as non-root
- set read-only root filesystem where possible
- drop Linux capabilities
- set CPU/memory requests and limits in Kubernetes
- do not mount Docker socket
- do not store secrets in images
- scan images
- use minimal base images
- keep base images patched

Kubernetes security context example:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

Interview line:

"Container security is layered: build a minimal image, run as non-root, restrict Linux privileges, avoid secrets in images, scan the artifact, and enforce runtime guardrails in Kubernetes."

## PID 1 And Signal Handling

The main process in a container runs as PID 1.

PID 1 has special signal behavior.

Why this matters:

- Kubernetes sends SIGTERM during pod shutdown
- app should handle SIGTERM gracefully
- app should stop accepting new work
- app should finish in-flight requests if possible
- after `terminationGracePeriodSeconds`, Kubernetes sends SIGKILL

Bad pattern:

```Dockerfile
CMD uvicorn src.main:app --host 0.0.0.0 --port 8080
```

Better:

```Dockerfile
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

Exec form avoids shell signal-handling surprises.

## ECR Mental Model

ECR is AWS's container image registry.

Pipeline:

```text
docker build
-> docker tag
-> aws ecr get-login-password
-> docker login
-> docker push
-> Kubernetes node pulls image from ECR
```

Manual commands:

```bash
aws ecr create-repository \
  --repository-name interview-app \
  --region us-east-1

aws ecr get-login-password --region us-east-1 \
  | docker login \
    --username AWS \
    --password-stdin 923988301700.dkr.ecr.us-east-1.amazonaws.com

docker build -t interview-app:manual-v1 .

docker tag interview-app:manual-v1 \
  923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1

docker push \
  923988301700.dkr.ecr.us-east-1.amazonaws.com/interview-app:manual-v1
```

Why no static ECR password?

`aws ecr get-login-password` returns a temporary authorization token generated from your AWS identity.

The credential comes from IAM permissions, not from a permanent ECR password.

## ECR Permissions

To push:

- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`
- `ecr:PutImage`

To pull:

- `ecr:GetAuthorizationToken`
- `ecr:BatchGetImage`
- `ecr:GetDownloadUrlForLayer`

In EKS:

- worker node role usually needs ECR pull permissions
- CI role needs ECR push permissions

## ImagePullBackOff

Meaning:

Kubernetes tried to pull the image, failed, then backed off before retrying.

Common causes:

- image tag does not exist
- ECR repo wrong
- image in wrong region/account
- node IAM role lacks ECR pull permission
- private registry auth missing
- node has no route to ECR
- architecture mismatch, such as arm64 image on amd64 node
- typo in image name

Commands:

```bash
kubectl describe pod <pod> -n <namespace>
aws ecr describe-images \
  --repository-name interview-app \
  --region us-east-1
kubectl get nodes -o wide
```

Interview answer:

"I start with `kubectl describe pod` because the event usually tells whether it is not found, denied, or network-related. Then I verify the image exists in ECR and that node IAM/network path can pull it."

## Vulnerability Scanning

Image scanning finds known CVEs in OS packages and language dependencies.

Common tools:

- ECR image scanning
- Amazon Inspector
- Trivy
- Grype
- Snyk

Pipeline pattern:

```text
build image
-> run unit tests
-> scan dependencies
-> scan container image
-> fail on critical vulnerabilities
-> push/deploy only if policy passes
```

Important:

Scanning does not prove the app is secure. It finds known vulnerabilities.

## SBOM

SBOM means Software Bill of Materials.

It lists what is inside the artifact:

- OS packages
- libraries
- versions
- sometimes licenses

Useful for:

- vulnerability response
- compliance
- supply-chain review

## Common Docker Commands

Build:

```bash
docker build -t app:local .
```

Run:

```bash
docker run --rm -p 8080:8080 app:local
```

Inspect:

```bash
docker inspect app:local
```

Logs:

```bash
docker logs <container>
```

Exec:

```bash
docker exec -it <container> sh
```

List images:

```bash
docker images
```

Show image history:

```bash
docker history app:local
```

Remove unused:

```bash
docker system prune
```

Build multi-arch:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <repo>:<tag> \
  --push .
```

## Interview Questions

### "How do you make Docker images smaller?"

Answer:

"Use smaller base images, multi-stage builds, `.dockerignore`, avoid unnecessary packages, clean package caches, avoid copying test/build files into runtime image, and use compiled/minimal runtime images where appropriate."

### "Why should containers run as non-root?"

Answer:

"If the app is compromised, root inside the container gives the attacker more ability to modify files, exploit mounted volumes, or combine with container escape vulnerabilities. Non-root is one layer of defense."

### "Why avoid latest?"

Answer:

"Because it is mutable. The same manifest can deploy different images at different times, making rollback, audit, and reproducibility harder."

### "How do you debug a container that works locally but fails in Kubernetes?"

Answer:

"I compare environment variables, command/args, exposed port, service targetPort, probes, secrets/configmaps, architecture, runtime user permissions, filesystem write paths, and dependency connectivity. Then I check pod events and logs."

## Final Mental Model

For Docker questions, always move through this chain:

```text
Dockerfile
-> image layers
-> registry
-> Kubernetes pull
-> container start
-> app process
-> probes/logs/resources/security
```

That keeps your answer structured.
