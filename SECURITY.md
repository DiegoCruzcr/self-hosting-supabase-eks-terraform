# Security

This document describes the **known security limitations of the default configuration** in this project. It is intended to help operators understand what is and is not protected before deploying to production.

> This is a self-hosted, infrastructure-as-code project. Security posture depends entirely on how you configure and deploy it. The defaults here are optimized for ease of getting started, **not for production hardness**.

---

## Known Limitations (Default Config)

### Network & TLS

**HTTP only — no TLS in front of Kong**

The ALB ingress is configured for plain HTTP on port 80 only:
```yaml
# terraform/modules/supabase-project/values.yaml.tpl
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
```
All traffic — including auth tokens, JWTs, and user data — travels unencrypted between clients and the load balancer.

*Remediation:* Add an ACM certificate ARN and add HTTPS (443) to `listen-ports`. Enable `ssl-redirect` to force HTTPS.

---

**ALB is internet-facing with no IP restriction**

The load balancer is reachable from any IP by default:
```yaml
alb.ingress.kubernetes.io/scheme: "internet-facing"
```
There is no `alb.ingress.kubernetes.io/inbound-cidrs` annotation restricting source IPs.

*Remediation:* Add `alb.ingress.kubernetes.io/inbound-cidrs: "x.x.x.x/32"` to the ingress annotations in `values.yaml.tpl`, or place a WAF in front of the ALB.

---

**No WAF**

No AWS WAF ACL is associated with the ALB. SQL injection, XSS, and volumetric abuse are not filtered at the load balancer layer.

*Remediation:* Associate a WAF Web ACL via `alb.ingress.kubernetes.io/wafv2-acl-arn`.

---

**No Kong rate limiting**

Kong is deployed with an empty config (`kong: {}`). No rate limiting plugin is configured. The API is open to brute-force and credential stuffing.

*Remediation:* Add Kong rate-limiting plugin config in the Helm values.

---

**DB connections without SSL (internal)**

All Supabase services connect to Postgres with SSL disabled:
```yaml
# values.yaml.tpl — applies to auth, rest, storage, meta, realtime, analytics
DB_SSL: "disable"
```
This is acceptable inside a Kubernetes namespace (traffic stays on the pod network), but means that any pod that can reach the DB service can connect without a TLS handshake.

*Remediation:* Enable `DB_SSL: "require"` and configure the Postgres pod accordingly if stricter intra-cluster security is needed.

---

**No Kubernetes NetworkPolicy**

No `NetworkPolicy` resources are created. All pods in a namespace can reach each other on any port. A compromised pod (e.g. Storage) could directly query the Postgres port of the DB pod.

*Remediation:* Add `NetworkPolicy` resources to allow only the expected service-to-service traffic.

---

### Authentication

**Public signup is enabled**

```yaml
# values.yaml.tpl
GOTRUE_DISABLE_SIGNUP: "false"
```
Anyone who reaches the ALB can create a user account.

*Remediation:* Set `GOTRUE_DISABLE_SIGNUP: "true"` if you don't want open registration. Use invite-only flows via the service role key instead.

---

**Email auto-confirmed — no verification step**

```yaml
# values.yaml.tpl
GOTRUE_MAILER_AUTOCONFIRM: "true"
```
Users are immediately active after signup. No email confirmation link is sent. This also means no SMTP server is required, but it removes an abuse-prevention layer.

*Remediation:* Set `GOTRUE_MAILER_AUTOCONFIRM: "false"` and configure an SMTP provider in the auth environment variables.

---

**OAuth redirect URI allowlist is wildcard**

```yaml
# values.yaml.tpl
GOTRUE_URI_ALLOW_LIST: "*"
```
Any redirect URI is accepted during OAuth flows. This can enable open redirect attacks if your OAuth providers are misconfigured.

*Remediation:* Set `GOTRUE_URI_ALLOW_LIST` to a comma-separated list of your actual frontend origins.

---

### Secrets & Credentials

**Single password for all Postgres roles**

The `authenticator_password` in `projects.auto.tfvars` is used as the master password for every Supabase internal role (`supabase_auth_admin`, `authenticator`, `supabase_storage_admin`, `supabase_admin`, etc.). Compromise of one service exposes all of them.

*Remediation:* This is a limitation of the `supabase/postgres` image initialization — separate per-role passwords require a custom Postgres init flow.

---

**Analytics service embeds DB password in env var**

```yaml
# values.yaml.tpl
POSTGRES_BACKEND_URL: "postgresql://supabase_admin:<password>@supabase-<project>-db:5432/_supabase"
```
The password is stored in a Kubernetes Secret (base64, not plaintext in etcd), but it is visible in plain text when running:
```bash
kubectl describe pod -n supabase-<project> <analytics-pod>
```

*Remediation:* Enable KMS envelope encryption for etcd on the EKS cluster to encrypt Secrets at rest.

---

**Kubernetes Secrets are not encrypted at rest by default**

EKS does not enable KMS envelope encryption for etcd Secrets unless explicitly configured. All JWT secrets, DB passwords, and API keys are stored as base64-encoded strings accessible to anyone with `kubectl get secret` permissions.

*Remediation:* Enable envelope encryption when creating the EKS cluster, or use AWS Secrets Manager with External Secrets Operator.

---

### IAM & S3

**IRSA is scoped to a single project bucket (intended)**

The Storage IRSA role (`supabase-storage-irsa-<project>`) is restricted to the specific project S3 bucket — not account-wide. This is correct behavior.

However, the IAM policy allows `s3:PutObject` and `s3:DeleteObject` on `bucket/*` with no prefix condition. A compromised Storage pod can overwrite any object in the project bucket.

*Remediation:* Add an `s3:prefix` condition if stricter per-tenant object isolation is needed within a single bucket.

---

**S3 versioning with no lifecycle policy**

```hcl
# terraform/modules/supabase-project/s3.tf
versioning { enabled = true }
```
Versioning is enabled (good for recovery), but there is no lifecycle rule to expire old versions or incomplete multipart uploads. Storage costs will grow unboundedly for frequently overwritten objects.

*Remediation:* Add an `aws_s3_bucket_lifecycle_configuration` resource to expire non-current versions after N days.

---

### Operational

**No pod security contexts**

No `securityContext` is set on any pod. Containers may run as root depending on the upstream image defaults.

*Remediation:* Add `securityContext: { runAsNonRoot: true }` in Helm values and validate against the upstream images.

---

**No CPU/memory resource limits**

No resource `limits` are configured in the Helm values. A single misbehaving pod (e.g. a slow query in analytics) can consume all CPU/memory on a node, affecting other projects on the same node.

*Remediation:* Set `resources.limits` and `resources.requests` per service in `values.yaml.tpl`.

---

## Summary Table

| Limitation | Severity | Default | Remediation |
|-----------|----------|---------|-------------|
| HTTP only, no TLS | Critical | On | ACM cert + HTTPS listener |
| Internet-facing ALB, no IP restriction | High | On | `inbound-cidrs` annotation or WAF |
| No WAF | High | Off | WAF Web ACL on ALB |
| No Kong rate limiting | High | Off | Kong rate-limit plugin |
| Public signup enabled | Medium | On | `GOTRUE_DISABLE_SIGNUP: "true"` |
| Email auto-confirm | Medium | On | `GOTRUE_MAILER_AUTOCONFIRM: "false"` + SMTP |
| Wildcard OAuth redirect | Medium | On | Explicit `GOTRUE_URI_ALLOW_LIST` |
| Single shared DB password | Medium | By design | Custom Postgres init (complex) |
| No NetworkPolicy | Medium | Off | Add per-namespace NetworkPolicy |
| K8s Secrets not encrypted at rest | Medium | Off | EKS KMS envelope encryption |
| Analytics password visible in env | Low | On | KMS encryption or External Secrets |
| No pod security contexts | Low | Off | `securityContext` in Helm values |
| No resource limits | Low | Off | `resources.limits` in Helm values |
| S3 versioning no lifecycle | Low | On | S3 lifecycle rule for non-current versions |
| DB_SSL disabled (intra-cluster) | Low | On | `DB_SSL: "require"` |

---

## Reporting a Vulnerability

This is a community infrastructure template. If you find a security issue in the Terraform modules, Helm values, or IAM policies:

1. **Do not open a public issue** with exploit details.
2. Open a GitHub issue with the title `[SECURITY]` and a description of the impact — omit specific exploit steps.
3. The maintainer will follow up to coordinate a fix before public disclosure.
