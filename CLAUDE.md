# Supabase Self-Hosted on AWS EKS

Self-hosted Supabase on AWS EKS with one Postgres pod per project (no Aurora).

## Architecture

```
Internet
    │
    ▼
AWS ALB (HTTP, per-project hostname)
    │
    ▼
EKS Cluster
├── Namespace: supabase-alpha
│   ├── Kong (API Gateway + Ingress)
│   ├── PostgREST, GoTrue, Realtime, Storage API, Meta, Studio, ImgProxy
│   └── supabase/postgres StatefulSet  ← DB pod (EBS PVC, gp2, 20Gi)
│
└── Namespace: supabase-beta
    ├── ... (same services)
    └── supabase/postgres StatefulSet
```

Each project is fully isolated: its own namespace, its own Postgres pod, its own S3 bucket.

## Stack

| Component | Technology |
|-----------|-----------|
| Compute | AWS EKS (t3.medium nodes) |
| Database | `supabase/postgres:15.8.1.085` StatefulSet (EBS-backed) |
| Storage | AWS S3 per project (IRSA — no static credentials) |
| Ingress | AWS ALB via Load Balancer Controller |
| IaC | Terraform >= 1.5 (run from `terraform/` dir) |

## Module Layout

```
terraform/
├── modules/
│   ├── vpc/              VPC, subnets, NAT GW, S3 endpoint
│   ├── eks/              EKS cluster, node group, IRSA, LBC + EBS CSI addons
│   └── supabase-project/ Helm release, S3 bucket, IRSA per project
└── envs/dev/             ← USE THIS for all terraform commands
    ├── main.tf
    ├── terraform.tfvars          non-secret config
    └── projects.auto.tfvars      per-project secrets (gitignored)
```

> `modules/aurora/` and `modules/aurora-db-init/` are kept on disk but not used.

## Prerequisites

- Terraform >= 1.5
- AWS CLI with credentials (IAM, EKS, EC2, S3)
- `kubectl` (for validation after apply)
- `helm` >= 3 (optional, for debugging)

## Terraform Commands

All commands run from the `terraform/` directory:

```bash
cd terraform

terraform init \
  -chdir=envs/dev

terraform plan \
  -var-file="envs/dev/projects.auto.tfvars" \
  -var-file="envs/dev/terraform.tfvars"

terraform apply \
  -var-file="envs/dev/projects.auto.tfvars" \
  -var-file="envs/dev/terraform.tfvars"
```

Apply order (automatic):
1. VPC
2. EKS
3. supabase-project (per project): S3 bucket, IRSA role, Helm release

## projects.auto.tfvars Schema

```hcl
projects = [
  {
    name                     = "alpha"
    jwt_secret               = "..."   # >= 32 chars random string
    anon_key                 = "..."   # JWT signed with jwt_secret, role=anon
    service_key              = "..."   # JWT signed with jwt_secret, role=service_role
    authenticator_password   = "..."   # postgres master password (all roles use this)
    studio_password          = "..."   # Supabase Studio login password
    realtime_enc_key         = "..."   # hex >= 32 chars
    realtime_secret_key_base = "..."   # >= 64 chars
  }
]
```

### Generating values

```bash
# jwt_secret, realtime_enc_key
openssl rand -hex 32

# authenticator_password, studio_password
openssl rand -base64 16

# realtime_secret_key_base
openssl rand -hex 64

# anon_key / service_key — Node.js
node -e "
const jwt = require('jsonwebtoken')
const s = 'YOUR_JWT_SECRET'
const exp = Math.floor(Date.now()/1000) + 10*365*24*3600
console.log('anon_key:   ', jwt.sign({role:'anon',iss:'supabase',iat:Math.floor(Date.now()/1000),exp},s))
console.log('service_key:', jwt.sign({role:'service_role',iss:'supabase',iat:Math.floor(Date.now()/1000),exp},s))
"
```

> Never commit `projects.auto.tfvars` with real secrets. In CI/CD use `TF_VAR_projects` env var.

## Validation (requires EKS connection)

```bash
# Connect to cluster first
aws eks update-kubeconfig --region us-east-1 --name supabase-eks

# Check pods
kubectl get pods -n supabase-alpha

# Check DB pod logs
kubectl logs -n supabase-alpha statefulset/supabase-alpha-db

# Check ingress (get ALB DNS)
kubectl get ingress -n supabase-alpha

# Health checks (replace <alb-dns>)
curl http://<alb-dns>/health
curl http://<alb-dns>/rest/v1/ -H "apikey: <anon_key>"
curl http://<alb-dns>/auth/v1/health
```

## Adding a New Project

Add a new entry to `projects` in `projects.auto.tfvars`, then:

```bash
terraform apply \
  -var-file="envs/dev/projects.auto.tfvars" \
  -var-file="envs/dev/terraform.tfvars"
```

Terraform creates only the new resources (new namespace, new DB pod, new S3 bucket, new Helm release).

## Security Notes

- `projects.auto.tfvars` is gitignored — never commit real secrets
- Storage API accesses S3 via IRSA (no static AWS keys)
- DB is internal (ClusterIP service, no external exposure)
- Kong ALB is internet-facing; restrict by IP in production via ALB annotations
