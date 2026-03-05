# Supabase Self-Hosted on AWS EKS

Self-hosted [Supabase](https://supabase.com/) on AWS EKS using Terraform — one Postgres pod per project, fully isolated by namespace. No Aurora, no managed RDS.

---

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
│   ├── Edge Runtime (functions)  ← EFS PVC (RWX, shared across replicas)
│   ├── Logflare (analytics)
│   ├── Vector (log collector)
│   └── supabase/postgres StatefulSet  ← DB pod (EBS PVC, gp2, 20Gi)
│
└── Namespace: supabase-beta
    ├── ... (same services)
    └── supabase/postgres StatefulSet
```

Each project is fully isolated: its own namespace, Postgres pod, and S3 bucket.

---

## Stack

| Component | Technology |
|-----------|------------|
| Compute | AWS EKS (t3.medium nodes) |
| Database | `supabase/postgres:15.8.1.085` StatefulSet (EBS-backed, 20Gi) |
| Storage | AWS S3 per project (IRSA — no static credentials) |
| Edge Functions | `supabase/edge-runtime:v1.70.3` + AWS EFS (RWX, per-project access point) |
| Ingress | AWS ALB via Load Balancer Controller |
| Analytics | Logflare + Vector (log shipping) |
| IaC | Terraform >= 1.5 |
| Helm chart | supabase-community/supabase v0.5.0 |

---

## Prerequisites

| Tool | Min version | Purpose |
|------|-------------|---------|
| Terraform | >= 1.5 | Manage infrastructure |
| AWS CLI | any | Credentials, EKS, S3 |
| `kubectl` | any | Validate pods after deploy |
| `helm` | >= 3 | Auto-installed by Terraform (optional for debug) |

**Required AWS permissions:** IAM, EKS, EC2 (VPC/SG/subnets), S3

---

## Module Layout

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

## Step-by-Step Setup

### 1. Fill in secrets

Create `terraform/envs/dev/projects.auto.tfvars`:

```hcl
projects = [
  {
    name = "alpha"

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

    # Public base URL (set after first apply — use ALB DNS from: kubectl get ingress -n supabase-<name>)
    external_url = "http://<alb-dns>"

    # pgsodium Vault encryption key
    vault_enc_key = "..."   # 32-char hex

    # pg-meta / Studio connection string encryption key
    meta_crypto_key = "..."  # 32-char hex

    # Logflare tokens — power the Logs tab in Studio
    logflare_public_token  = "..."  # 64-char hex
    logflare_private_token = "..."  # 64-char hex
  }
]
```

#### Generating each value

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

const anonKey    = jwt.sign({ role: 'anon',         iss: 'supabase', iat: Math.floor(Date.now()/1000), exp }, secret)
const serviceKey = jwt.sign({ role: 'service_role', iss: 'supabase', iat: Math.floor(Date.now()/1000), exp }, secret)

console.log('anon_key:   ', anonKey)
console.log('service_key:', serviceKey)
```

**`authenticator_password`** and **`studio_password`** — random strings >= 16 chars:
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

**`vault_enc_key`** and **`meta_crypto_key`** — 32-char hex:
```bash
openssl rand -hex 16
```

**`logflare_public_token`** and **`logflare_private_token`** — 64-char hex:
```bash
openssl rand -hex 32
```

> **Never commit `projects.auto.tfvars` with real secrets.**
> In CI/CD pass secrets via environment variable:
> ```bash
> export TF_VAR_projects='[{"name":"alpha","jwt_secret":"..."}]'
> ```

---

### 2. Configure region and cluster (optional)

Edit `terraform/envs/dev/terraform.tfvars` to override defaults:

```hcl
aws_region             = "us-east-1"
cluster_name           = "supabase-eks"
eks_node_instance_type = "t3.medium"
eks_node_desired_size  = 2
```

---

### 3. Run Terraform

All commands run from the `terraform/` directory:

```bash
cd terraform

# Download providers and modules
terraform init -chdir=envs/dev

# Preview what will be created
terraform -chdir=envs/dev plan \
  -var-file="projects.auto.tfvars" \
  -var-file="terraform.tfvars"

# Create infrastructure
terraform -chdir=envs/dev apply \
  -var-file="projects.auto.tfvars" \
  -var-file="terraform.tfvars"

# Destroy infrastructure
terraform -chdir=envs/dev destroy \
  -var-file="projects.auto.tfvars" \
  -var-file="terraform.tfvars"
```

Apply order (automatic):
1. **VPC** — base network
2. **EKS** — cluster, node group, addons (LBC + EBS CSI + EFS CSI), EFS file system + mount targets
3. **supabase-project** (per project): namespace, EFS access point, PV/PVC, S3 bucket, IRSA role, Helm release

---

## Post-Deploy Validation

**Connect to EKS cluster first:**
```bash
aws eks update-kubeconfig --region us-east-1 --name supabase-eks
```

```bash
# All pods running?
kubectl get pods -n supabase-alpha

# DB pod logs
kubectl logs -n supabase-alpha statefulset/supabase-alpha-db

# Kong ALB ingress — get ALB DNS
kubectl get ingress -n supabase-alpha

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

> After the first apply, copy the ALB DNS and set `external_url` in `projects.auto.tfvars`, then run `terraform apply` again so Studio and Auth have the correct public URL.

---

## Deploying Edge Functions

Edge Functions run on `supabase/edge-runtime` and are served at `/functions/v1/<name>`. Each project has an EFS volume mounted at `/home/deno/functions/` — **the function name is the directory name**.

```
/home/deno/functions/
├── main/          ← built-in router (managed by the chart, do not modify)
├── hello/         ← available at /functions/v1/hello
└── send-email/    ← available at /functions/v1/send-email
```

### Deploy a function

```bash
# Connect to cluster
aws eks update-kubeconfig --region us-east-1 --name supabase-eks

# Copy a local function directory into the pod
kubectl cp ./my-function/ \
  supabase-alpha/$(kubectl get pod -n supabase-alpha -l app.kubernetes.io/name=functions -o jsonpath='{.items[0].metadata.name}'):/home/deno/functions/my-function/
```

No restart required — the edge runtime picks up new directories automatically. Since the volume is EFS (ReadWriteMany), all autoscaled replicas see the new function immediately.

### Deploy a function (Linux / CI-CD)

Recommended for CI/CD pipelines (GitHub Actions, GitLab CI, etc.). Use a tar pipe — more portable than `kubectl cp`:

```bash
# From the directory containing your function folder
cd path/to/supabase/functions

POD=$(kubectl get pod -n supabase-alpha -l app.kubernetes.io/name=functions -o jsonpath='{.items[0].metadata.name}')

tar cf - my-function | kubectl exec -i -n supabase-alpha "$POD" -- \
  tar xf - --no-same-owner -C /home/deno/functions/
```

- `--no-same-owner` — avoids permission errors when the container runs as a different UID

### Deploy a function (Windows / Git Bash)

`kubectl cp` does not work correctly on Windows. Use a tar pipe instead:

```bash
# From the directory containing your function folder
cd path/to/supabase/functions

POD=$(kubectl get pod -n supabase-alpha -l app.kubernetes.io/name=functions -o jsonpath='{.items[0].metadata.name}')

tar cf - my-function | MSYS_NO_PATHCONV=1 kubectl exec -i -n supabase-alpha "$POD" -- \
  tar xf - --no-same-owner -C /home/deno/functions/
```

- `MSYS_NO_PATHCONV=1` — prevents Git Bash from converting Unix paths to Windows paths
- `--no-same-owner` — avoids ownership errors when extracting as a different UID

### Get the anon key

```bash
kubectl get secret supabase-alpha-jwt -n supabase-alpha \
  -o jsonpath='{.data.anonKey}' | base64 -d
```

### Rollout (force restart if needed)

```bash
kubectl rollout restart deployment -n supabase-alpha \
  $(kubectl get deploy -n supabase-alpha -l app.kubernetes.io/name=functions -o jsonpath='{.items[0].metadata.name}')
```

### Call the function

```bash
curl http://<ALB-DNS>/functions/v1/my-function \
  -H "Authorization: Bearer <anon_key>"
```

### Verify the volume is mounted

```bash
kubectl describe pod -n supabase-alpha \
  $(kubectl get pod -n supabase-alpha -l app.kubernetes.io/name=functions -o jsonpath='{.items[0].metadata.name}') \
  | grep -A5 Mounts
```

---

## Adding a New Project

Add a second object to the `projects` array in `projects.auto.tfvars`:

```hcl
projects = [
  {
    name = "alpha"
    # ... alpha fields
  },
  {
    name                     = "beta"
    jwt_secret               = "..."
    anon_key                 = "..."
    service_key              = "..."
    authenticator_password   = "..."
    studio_password          = "..."
    realtime_enc_key         = "..."
    realtime_secret_key_base = "..."
    external_url             = "http://<alb-dns>"
    vault_enc_key            = "..."
    meta_crypto_key          = "..."
    logflare_public_token    = "..."
    logflare_private_token   = "..."
  }
]
```

Then run `terraform apply`. Terraform creates only the new resources without recreating existing ones.

---

## Security

See [SECURITY.md](SECURITY.md) for a full list of known limitations in the default configuration, including network exposure, auth settings, secrets handling, and IAM scope — with remediation steps for each.

Quick summary:
- `projects.auto.tfvars` is **gitignored** — never commit real secrets
- Storage API accesses S3 via **IRSA** — no static AWS keys in pods
- Postgres is **ClusterIP only** — not reachable outside the namespace
- **Default config is not production-ready** — HTTP only, public signup open, no rate limiting. Review [SECURITY.md](SECURITY.md) before going live.
