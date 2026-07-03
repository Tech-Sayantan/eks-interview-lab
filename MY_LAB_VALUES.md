# My Lab Values

Use these values for this lab.

Important correction:

- `us-east-a` is not a valid AWS region.
- Use `us-east-1` unless you intentionally want another region.
- `us-east-1a` is an Availability Zone, not a region.

## Chosen Values

```text
AWS region: us-east-1
AWS account ID: 923988301700
Domain name: tanscape.online
App hostname: app.tanscape.online
Route 53 hosted zone name: tanscape.online
GitHub username: Tech-Sayantan
GitHub repo name: eks-interview-lab
Cluster name: interview-eks
AWS CLI profile name: eks-lab
Kubernetes namespace: interview
Helm release name: interview-app
ECR repository name: interview-app
```

## Why App Hostname Is app.tanscape.online

You own:

```text
tanscape.online
```

So the app should be a subdomain of that domain:

```text
app.tanscape.online
```

Do not use:

```text
app.example.com
```

`example.com` is only documentation/example text.

## Next Step

Configure/check AWS CLI with the `eks-lab` profile:

```bash
aws sts get-caller-identity --profile eks-lab
```

If that fails, run:

```bash
aws configure --profile eks-lab
```

Use the IAM user CSV values locally. Do not paste the secret key anywhere.
