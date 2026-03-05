#!/usr/bin/env bash
# test-supabase.sh — End-to-end health check for supabase-alpha on EKS
set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
NAMESPACE="supabase-alpha"
CLUSTER_NAME="supabase-eks"
REGION="us-east-1"
HOST="alpha.example.com"
ANON_KEY=""

# ─── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# ─── Step 0: Connect to EKS ───────────────────────────────────────────────────
info "Connecting to EKS cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null
pass "kubeconfig updated"

# ─── Step 1: Pod health ───────────────────────────────────────────────────────
echo ""
info "=== Step 1: Pod health in namespace $NAMESPACE ==="
kubectl get pods -n "$NAMESPACE"

TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "Running" || true)
echo ""
if [ "$RUNNING" -eq "$TOTAL" ]; then
  pass "All $TOTAL pods are Running"
else
  fail "$RUNNING / $TOTAL pods Running — check logs with: kubectl logs -n $NAMESPACE <pod-name>"
fi

# ─── Step 2: PVC status ───────────────────────────────────────────────────────
echo ""
info "=== Step 2: PVC status (EBS volume for Postgres) ==="
kubectl get pvc -n "$NAMESPACE"
BOUND=$(kubectl get pvc -n "$NAMESPACE" --no-headers | grep -c "Bound" || true)
if [ "$BOUND" -ge 1 ]; then
  pass "PVC is Bound (EBS volume provisioned)"
else
  fail "PVC not Bound — EBS CSI driver may have an issue"
fi

# ─── Step 3: Ingress / ALB address ────────────────────────────────────────────
echo ""
info "=== Step 3: Ingress (ALB address) ==="
kubectl get ingress -n "$NAMESPACE"
ALB=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$ALB" ]; then
  fail "ALB address not yet assigned — wait 2-3 minutes and re-run"
  exit 1
else
  pass "ALB DNS: $ALB"
fi

# ─── Step 4: Kong gateway ─────────────────────────────────────────────────────
echo ""
info "=== Step 4: Kong API gateway ==="
KONG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  http://"$ALB"/ -H "Host: $HOST" || echo "000")
echo "  HTTP status: $KONG_STATUS"
if [[ "$KONG_STATUS" =~ ^(200|301|302|401|404)$ ]]; then
  pass "Kong is responding (status $KONG_STATUS — 401 means Kong is up and enforcing auth)"
else
  fail "Kong not reachable (status $KONG_STATUS)"
fi

# ─── Step 5: Auth service ─────────────────────────────────────────────────────
echo ""
info "=== Step 5: Auth service (GoTrue) ==="
AUTH_RESP=$(curl -s --max-time 10 \
  http://"$ALB"/auth/v1/health \
  -H "Host: $HOST" \
  -H "apikey: $ANON_KEY" || echo "ERROR")
echo "  Response: $AUTH_RESP"
if echo "$AUTH_RESP" | grep -q "version"; then
  pass "Auth service healthy"
else
  fail "Auth service not responding correctly"
fi

# ─── Step 6: REST API (PostgREST) ─────────────────────────────────────────────
echo ""
info "=== Step 6: REST API (PostgREST) ==="
REST_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  http://"$ALB"/rest/v1/ \
  -H "Host: $HOST" \
  -H "apikey: $ANON_KEY" || echo "000")
echo "  HTTP status: $REST_STATUS"
if [[ "$REST_STATUS" == "200" ]]; then
  pass "PostgREST responding (status 200)"
else
  fail "PostgREST returned status $REST_STATUS"
fi

# ─── Step 7: DB connectivity via postgres-meta ───────────────────────────────
echo ""
info "=== Step 7: DB connectivity (postgres-meta) ==="
META_SVC="supabase-${NAMESPACE#supabase-}-supabase-meta"
kubectl port-forward -n "$NAMESPACE" "svc/$META_SVC" 18080:8080 >/dev/null 2>&1 &
PF_PID=$!
sleep 2
DB_RESP=$(curl -s --max-time 10 http://localhost:18080/tables 2>/dev/null || echo "ERROR")
kill "$PF_PID" 2>/dev/null || true
if echo "$DB_RESP" | grep -q "\["; then
  pass "postgres-meta connected to DB successfully"
  echo "  Tables: $(echo "$DB_RESP" | head -c 200)..."
else
  fail "postgres-meta could not reach DB: $DB_RESP"
fi

# ─── Step 8: Studio HTTP check ────────────────────────────────────────────────
echo ""
info "=== Step 8: Studio admin UI ==="
STUDIO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  http://"$ALB"/ \
  -H "Host: $HOST" || echo "000")
echo "  HTTP status: $STUDIO_STATUS"
if [[ "$STUDIO_STATUS" =~ ^(200|301|302|401)$ ]]; then
  pass "Studio reachable (status $STUDIO_STATUS — 401 means login required, which is correct)"
else
  fail "Studio returned status $STUDIO_STATUS"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
info "=== Done. To open Studio in browser, use: ==="
echo "  http://$ALB"
echo ""
info "=== Or test with curl using Host header: ==="
echo "  curl http://$ALB/rest/v1/ -H 'Host: $HOST' -H 'apikey: $ANON_KEY'"
