# crystal-node

A production-pattern AWS platform built on EKS. Designed as a reusable foundation for deploying containerized applications with secure networking, GitOps-based deployments, and full observability.

Two applications are currently running on the platform:

- `api.chavastyle.com` — crystal-app (platform demo)
- `fit.chavastyle.com` — fit-link (FastAPI workout tracker)

---

## Architecture

```
User (internet)
  -> HTTPS
Route53 — api.chavastyle.com
  -> A alias record
API Gateway (HTTP API, TLS terminates here)
  -> VPC Link (private tunnel)
NLB (internal, no public IP)
  -> NodePort on EC2 worker nodes
Kubernetes Service
  -> label selector
Pods (private subnets, non-root, resource limits)
```

All cluster resources are private. The only ingress path is through API Gateway. Worker nodes have no public IPs and the EKS API server has no public endpoint.

**Stack:** Terraform, EKS, API Gateway, Route53, ACM, S3, ArgoCD, Prometheus, Grafana, CloudWatch, GitHub Actions, ECR

---

## Repository structure

```
crystal-node/
├── bootstrap/              # State backend setup: run once
│   └── initialize_aws.sh
├── environments/
│   └── dev/                # Terraform entrypoint
│       ├── main.tf
│       ├── variables.tf
│       ├── locals.tf
│       ├── outputs.tf
│       └── terraform.tfvars  # not committed, see Prerequisites
├── modules/
│   ├── vpc/                # VPC, subnets, IGW, NAT, routing
│   ├── eks/                # EKS cluster, node groups, IAM, OIDC
│   ├── lb-controller/      # AWS Load Balancer Controller via Helm + Pod Identity
│   ├── s3/                 # Application S3 bucket
│   ├── api-gw/             # HTTP API Gateway with VPC Link
│   ├── route53/            # Hosted zone, ACM cert, custom domain
│   ├── observability/      # Prometheus, Grafana, CloudWatch Container Insights
│   ├── security/           # Network policies, Pod Security Standards, Secrets Manager
│   ├── cicd/               # ECR repositories, GitHub Actions IAM federation
│   └── argocd/             # ArgoCD GitOps controller
├── k8s/
│   ├── crystal-app/        # Deployment and Service for crystal-app
│   └── fit-link/           # Deployment and Service for fit-link
├── scripts/
│   ├── health-check.sh     # Validates tools, credentials, and cluster connectivity
│   └── teardown.sh         # Ordered teardown: handles NLBs, security groups, finalizers

```

---

## Prerequisites

**Tools required:**
- AWS CLI >= 2.x configured with appropriate credentials
- Terraform >= 1.5
- kubectl >= 1.28
- Helm >= 3.12
- eksctl (for initial setup only)

**AWS permissions required:**
- EC2, EKS, IAM, S3, DynamoDB, ECR, API Gateway, Route53, ACM, Secrets Manager, CloudWatch

**State backend:**
The remote state backend must exist before any Terraform operations. Run once per AWS account:

```bash
cd bootstrap
bash initialize_aws.sh
```

This creates the S3 state bucket and DynamoDB lock table and generates `environments/dev/backend.tf`.

**Local variable file:**
Create `environments/dev/terraform.tfvars` with the following. This file is gitignored and must never be committed.

```hcl
grafana_password = "yourpassword"
db_password      = "yourdbpassword"
api_key          = "yourapikey"
github_org       = "your-github-username"
github_repo      = "crystal-node"
```

---

## Deployment

The deployment is split into two stages because API Gateway depends on an NLB that is created by Kubernetes, not Terraform. The NLB must exist before Terraform can wire up API Gateway.

**Stage 1: core infrastructure:**

```bash
cd environments/dev
terraform init
terraform apply
```

This deploys VPC, EKS, S3, LB Controller, observability, security, ArgoCD, and CI/CD. API Gateway and Route53 are skipped.

**After apply:**

```bash
# Update kubeconfig: the cluster endpoint changes on every fresh deploy
aws eks update-kubeconfig --region us-east-1 --name crystal-cluster

# Deploy applications: this triggers NLB provisioning
kubectl apply -f k8s/crystal-app/app.yaml
kubectl apply -f k8s/fit-link/deployment.yaml

# Wait for NLBs to provision: watch for EXTERNAL-IP to appear
kubectl get svc -n crystal-app -w
kubectl get svc -n fit-link -w
```

**Stage 2 — API Gateway and Route53:**

```bash
terraform apply -var="deploy_api_gw=true"
```

**Verify:**

```bash
curl https://api.chavastyle.com
curl https://fit.chavastyle.com/health
```

---

## Teardown

Always use the teardown script. Running `terraform destroy` directly without cleaning up Kubernetes-managed AWS resources (NLBs, security groups) will result in VPC deletion failures.

```bash
cd environments/dev
bash ../../scripts/teardown.sh
```

The script handles the following in order:
1. Removes ArgoCD application and namespace finalizers
2. Deletes Kubernetes services to trigger NLB deprovisioning
3. Empties ECR repositories
4. Waits for NLBs to be fully deleted in AWS (5 minute timeout)
5. Deletes leftover LB Controller security groups
6. Runs `terraform destroy`

**Route53 hosted zone:** The hosted zone for `chavastyle.com` is a data source in Terraform. It survives `terraform destroy` intentionally, nameservers never change and the registrar does not need to be updated between sessions.

---

## CI/CD pipeline

Every push to `master` in this repo triggers the GitHub Actions workflow in `.github/workflows/deploy.yml`.

The pipeline:
1. Authenticates to AWS via OIDC federation... no long-lived credentials stored in GitHub
2. Builds a Docker image tagged with the git commit SHA
3. Pushes the image to ECR
4. Updates the image tag in `k8s/crystal-app/app.yaml` and commits back to the repo
5. ArgoCD detects the new commit and syncs the cluster automatically

The fit-link application has its own pipeline in the `fit-link` repository which follows the same pattern and updates `k8s/fit-link/deployment.yaml` in this repo.

**Required GitHub secrets:**
- `AWS_ROLE_ARN`: IAM role ARN output from `terraform output github_actions_role_arn`

---

## Adding a new application

1. Create a new directory under `k8s/` with a Deployment and Service manifest
2. Add an ArgoCD Application resource to `modules/argocd/main.tf` pointing at that directory
3. Add an ECR repository to `modules/cicd/main.tf`
4. Add the new repo to the GitHub Actions OIDC trust policy in `modules/cicd/main.tf`
5. Add a new `module "api_gw_*"` and `module "route53_*"` call in `environments/dev/main.tf` for the subdomain
6. Create a GitHub Actions workflow in the application's own repository

The shared platform infrastructure: VPC, EKS, monitoring, security... requires no changes.

---

## Observability

**Grafana:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Access at `http://localhost:3000`. Pre-built Kubernetes dashboards are available under Dashboards > Browse > Kubernetes.

**CloudWatch:**

Container logs, performance metrics, and host metrics are shipped to CloudWatch under:
```
/aws/containerinsights/crystal-cluster/application
/aws/containerinsights/crystal-cluster/performance
/aws/containerinsights/crystal-cluster/host
```

---

## Known issues and workarounds

**ImagePullBackOff after fresh deploy**: ECR is empty because the pipeline hasn't run yet. Trigger it with an empty commit or push any change to master.

**NLB stuck in pending**: check LB Controller logs: `kubectl logs -n kube-system deployment/aws-load-balancer-controller | grep -i error`

**State lock not released**: `terraform force-unlock <lock-id>` from the error message

**ACM certificate stuck on PENDING_VALIDATION**: verify the registrar nameservers match the current hosted zone: `dig chavastyle.com NS` vs `aws route53 get-hosted-zone --id <zone-id> --query 'DelegationSet.NameServers'`

---

