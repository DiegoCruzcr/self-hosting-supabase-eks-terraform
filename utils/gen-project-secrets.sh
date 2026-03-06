#!/usr/bin/env bash
# gen-project-secrets.sh — Generate all secrets for a new Supabase project
#
# Usage:
#   ./utils/gen-project-secrets.sh <project-name> [alb-port]
#
# All projects share one ALB via group.name=supabase-shared.
# Each project must use a unique port (alpha=80, beta=8080, gamma=8081, ...)
#
# Output: ready-to-paste HCL block for projects.auto.tfvars
#
# Requirements: openssl, python3 (for JWT generation, no extra packages needed)

set -euo pipefail

PROJECT_NAME="${1:-}"
if [[ -z "$PROJECT_NAME" ]]; then
  echo "Usage: $0 <project-name>"
  exit 1
fi

# ── Generate raw secrets ─────────────────────────────────────────────────────
JWT_SECRET=$(openssl rand -hex 32)
REALTIME_ENC=$(openssl rand -hex 8)          # 16 hex chars = valid 16-char key
REALTIME_BASE=$(openssl rand -hex 64)        # 128 hex chars >= 64 required
AUTH_PASS=$(openssl rand -base64 12 | tr -d '/+=\n')
STUDIO_PASS=$(openssl rand -hex 16)
VAULT_KEY=$(openssl rand -hex 16)            # 32 hex chars
META_KEY=$(openssl rand -hex 16)             # 32 hex chars
LOG_PUB=$(openssl rand -hex 32)
LOG_PRIV=$(openssl rand -hex 32)

# ── Generate JWTs using Python (no npm dependency) ───────────────────────────
ANON_KEY=$(python - <<PYEOF
import json, hmac, hashlib, base64, time

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

secret = "$JWT_SECRET"
now = int(time.time())
exp = now + 10 * 365 * 24 * 3600

def make_jwt(role):
    header = b64url(json.dumps({"alg":"HS256","typ":"JWT"},separators=(',',':')))
    payload = b64url(json.dumps({"role":role,"iss":"supabase","iat":now,"exp":exp},separators=(',',':')))
    msg = f"{header}.{payload}".encode()
    sig = b64url(hmac.new(secret.encode(), msg, hashlib.sha256).digest())
    return f"{header}.{payload}.{sig}"

print(make_jwt("anon"))
PYEOF
)

SERVICE_KEY=$(python - <<PYEOF
import json, hmac, hashlib, base64, time

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

secret = "$JWT_SECRET"
now = int(time.time())
exp = now + 10 * 365 * 24 * 3600

def make_jwt(role):
    header = b64url(json.dumps({"alg":"HS256","typ":"JWT"},separators=(',',':')))
    payload = b64url(json.dumps({"role":role,"iss":"supabase","iat":now,"exp":exp},separators=(',',':')))
    msg = f"{header}.{payload}".encode()
    sig = b64url(hmac.new(secret.encode(), msg, hashlib.sha256).digest())
    return f"{header}.{payload}.{sig}"

print(make_jwt("service_role"))
PYEOF
)

# ── Print HCL block ──────────────────────────────────────────────────────────
echo ""
echo "# ── Copy this block into terraform/envs/dev/projects.auto.tfvars ──────────"
ALB_PORT="${2:-80}"

cat <<HCL
  {
    name                     = "$PROJECT_NAME"
    jwt_secret               = "$JWT_SECRET"
    anon_key                 = "$ANON_KEY"
    service_key              = "$SERVICE_KEY"
    authenticator_password   = "$AUTH_PASS"
    studio_password          = "$STUDIO_PASS"
    realtime_enc_key         = "$REALTIME_ENC"
    realtime_secret_key_base = "$REALTIME_BASE"
    external_url             = "http://placeholder:$ALB_PORT"  # replace placeholder with shared ALB DNS after apply
    vault_enc_key            = "$VAULT_KEY"
    meta_crypto_key          = "$META_KEY"
    logflare_public_token    = "$LOG_PUB"
    logflare_private_token   = "$LOG_PRIV"
    alb_port                 = $ALB_PORT
  }
HCL
echo "# ────────────────────────────────────────────────────────────────────────────"
echo ""
echo "All projects share one ALB (group.name=supabase-shared)."
echo "After terraform apply, get the shared ALB DNS:"
echo "  kubectl get ingress -n supabase-$PROJECT_NAME -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo "Then update external_url to: http://<alb-dns>:$ALB_PORT"
