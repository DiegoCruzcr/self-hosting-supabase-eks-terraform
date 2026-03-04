# Supabase Self-Hosted — Terraform Infrastructure

Terraform to run **Supabase** on AWS with:

- **EKS** — runs all Supabase microservices
- **supabase/postgres pod** — one Postgres StatefulSet per project namespace (EBS-backed)
- **ALB (Application Load Balancer)** — publicly accessible via HTTP, routed per project hostname
- **Multi-tenant by namespace** — each project gets its own namespace, Postgres pod, and S3 bucket

```
Internet
    │
    ▼
AWS ALB (HTTP)
    │  (routed by hostname per project)
    ▼
EKS Cluster
├── Namespace: supabase-alpha
│   ├── Kong (API Gateway)
│   ├── PostgREST, GoTrue, Realtime, Storage, Meta, Studio
│   └── supabase/postgres StatefulSet (EBS PVC)
│
└── Namespace: supabase-beta
    ├── Kong, PostgREST, GoTrue, Realtime, Storage, Meta, Studio
    └── supabase/postgres StatefulSet (EBS PVC)
```

---

## Prerequisites

| Tool | Min version | Purpose |
|------|-------------|---------|
| Terraform | >= 1.5 | Manage infrastructure |
| AWS CLI | any | Credentials, EKS, S3 |
| `kubectl` | any | Validate pods after deploy |
| `helm` | >= 3 | Auto-installed by Terraform (optional for debug) |

### Required AWS permissions

```
IAM, EKS, EC2 (VPC/SG/subnets), S3
```

---

## Module Structure

```
terraform/
├── versions.tf          # Providers and versions
├── variables.tf         # Root module variables
├── main.tf              # Module composition
├── outputs.tf           # Root module outputs
│
├── modules/
│   ├── vpc/             # VPC, public/private subnets, NAT GW, S3 endpoint
│   ├── eks/             # EKS cluster, node group, IRSA, LBC + EBS CSI addons
│   └── supabase-project/# Helm release per project + S3 bucket + IRSA for Storage
│
└── envs/
    └── dev/             # <<< USE THIS for terraform commands
        ├── main.tf
        ├── terraform.tfvars      # Non-secret config
        └── projects.auto.tfvars  # Per-project secrets (gitignored)
```

---

## Step by Step

### 1. Fill in secrets

Edit `terraform/envs/dev/projects.auto.tfvars`:

```hcl
projects = [
  {
    name = "my-project"

    # JWT — signs public API tokens
    jwt_secret  = "..."   # random string >= 32 chars
    anon_key    = "..."   # JWT with role=anon signed by jwt_secret
    service_key = "..."   # JWT with role=service_role signed by jwt_secret

    # Single postgres password (used for all Supabase roles by supabase/postgres image)
    authenticator_password = "..."   # random string >= 16 chars
    studio_password        = "..."   # Supabase Studio login password

    # Realtime keys
    realtime_enc_key         = "..."  # hex >= 32 chars
    realtime_secret_key_base = "..."  # string >= 64 chars
  }
]
```

#### How to generate each value

**`jwt_secret`** — random string >= 32 chars:
```bash
openssl rand -hex 32
```

**`anon_key`** and **`service_key`** — JWTs signed with `jwt_secret`:

```js
// npm install jsonwebtoken
const jwt = require('jsonwebtoken')
const secret = 'YOUR_JWT_SECRET_HERE'
const exp = Math.floor(Date.now()/1000) + 10*365*24*3600

const anonKey = jwt.sign({ role: 'anon', iss: 'supabase', iat: Math.floor(Date.now()/1000), exp }, secret)
const serviceKey = jwt.sign({ role: 'service_role', iss: 'supabase', iat: Math.floor(Date.now()/1000), exp }, secret)
console.log('anon_key:   ', anonKey)
console.log('service_key:', serviceKey)
```

**Passwords** — random strings >= 16 chars:
```bash
openssl rand -base64 16
```

**`realtime_enc_key`** — 32+ byte hex:
```bash
openssl rand -hex 32
```

**`realtime_secret_key_base`** — 64+ char string:
```bash
openssl rand -hex 64
```

> **Important:** Never commit `projects.auto.tfvars` with real secrets.
> In CI/CD, pass secrets via environment variable:
> ```bash
> export TF_VAR_projects='[{"name":"my-project","jwt_secret":"..."}]'
> ```

---

### 2. Configure region and cluster (optional)

Edit `terraform/envs/dev/terraform.tfvars` to change defaults:

```hcl
aws_region             = "us-east-1"
cluster_name           = "supabase-eks"
eks_node_instance_type = "t3.medium"
eks_node_desired_size  = 2
```

---

### 3. Run Terraform

All commands from the `terraform/` directory:

```bash
cd terraform

# Download providers and modules
terraform init -chdir=envs/dev

# Preview what will be created
terraform plan \
  -var-file="envs/dev/projects.auto.tfvars" \
  -var-file="envs/dev/terraform.tfvars"

# Create infrastructure
terraform apply \
  -var-file="envs/dev/projects.auto.tfvars" \
  -var-file="envs/dev/terraform.tfvars"
```

Apply order (automatic):
1. **VPC** — base network
2. **EKS** — cluster and nodes
3. **supabase-project** (per project): S3 bucket, IRSA role, Helm release (includes Postgres pod)

---

## Post-Deploy Validation

**Connect to EKS cluster first:**
```bash
aws eks update-kubeconfig --region us-east-1 --name supabase-eks
```

```bash
# Pods running in EKS
kubectl get pods -n supabase-my-project

# DB pod logs
kubectl logs -n supabase-my-project statefulset/supabase-my-project-db

# Kong ALB ingress (get DNS)
kubectl get ingress -n supabase-my-project

# Health checks (replace <ALB-DNS>)
curl http://<ALB-DNS>/health
curl http://<ALB-DNS>/rest/v1/ -H "apikey: <anon_key>"
curl http://<ALB-DNS>/auth/v1/health

# Create a test user
curl -X POST http://<ALB-DNS>/auth/v1/signup \
  -H "apikey: <anon_key>" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password1234"}'
```

---

## Adding a New Project

Add a second object to the `projects` array in `projects.auto.tfvars`:

```hcl
projects = [
  {
    name = "project-alpha"
    # ... alpha fields
  },
  {
    name                     = "project-beta"
    jwt_secret               = "..."
    anon_key                 = "..."
    service_key              = "..."
    authenticator_password   = "..."
    studio_password          = "..."
    realtime_enc_key         = "..."
    realtime_secret_key_base = "..."
  }
]
```

Then run `terraform apply`. Terraform creates only the new resources without recreating existing ones.

---

## Security

- `projects.auto.tfvars` is gitignored — never commit real secrets
- Storage API accesses S3 via **IRSA** (IAM Role for Service Accounts) — no static AWS keys
- Kong ALB is internet-facing; restrict access by IP in production via ALB annotations
- Postgres is exposed only as ClusterIP (internal to the namespace, not reachable externally)
