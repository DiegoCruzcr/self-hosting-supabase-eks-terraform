# ─── Disable bundled PostgreSQL pod ───────────────────────────────────────────
# CRITICAL: Aurora Serverless v2 is the database; no PostgreSQL pod in Kubernetes.
db:
  enabled: false

# ─── Secrets ──────────────────────────────────────────────────────────────────
secret:
  jwt:
    anonKey:    "${anon_key}"
    serviceKey: "${service_key}"
    secret:     "${jwt_secret}"
  db:
    username: "authenticator"
    password: "${authenticator_password}"
    database: "${project_name}"
  dashboard:
    username: "supabase"
    password: "${studio_password}"

# ─── Studio (Admin Dashboard) ─────────────────────────────────────────────────
studio:
  environment:
    SUPABASE_PUBLIC_URL:       "http://${project_name}.example.com"
    STUDIO_PG_META_URL:        "http://supabase-${project_name}-meta.supabase-${project_name}.svc.cluster.local:8080"
    DEFAULT_ORGANIZATION_NAME: "${project_name}"
    DEFAULT_PROJECT_NAME:      "${project_name}"
    NEXT_PUBLIC_ENABLE_LOGS:   "true"

# ─── Auth (GoTrue) ────────────────────────────────────────────────────────────
auth:
  environment:
    API_EXTERNAL_URL:              "http://${project_name}.example.com"
    GOTRUE_SITE_URL:               "http://${project_name}.example.com"
    GOTRUE_URI_ALLOW_LIST:         "*"
    GOTRUE_DISABLE_SIGNUP:         "false"
    GOTRUE_JWT_DEFAULT_GROUP_NAME: "authenticated"
    GOTRUE_JWT_ADMIN_ROLES:        "service_role"
    GOTRUE_JWT_AUD:                "authenticated"
    GOTRUE_JWT_EXP:                "3600"
    GOTRUE_MAILER_AUTOCONFIRM:     "true"
    GOTRUE_EXTERNAL_EMAIL_ENABLED: "false"
    DB_HOST:   "${aurora_host}"
    DB_PORT:   "5432"
    DB_NAME:   "${project_name}"
    DB_USER:   "supabase_auth_admin"
    DB_SSL:    "require"
    DB_DRIVER: "postgres"

# ─── PostgREST (REST API) ─────────────────────────────────────────────────────
rest:
  environment:
    DB_HOST:                       "${aurora_host}"
    DB_PORT:                       "5432"
    DB_NAME:                       "${project_name}"
    DB_USER:                       "authenticator"
    DB_SSL:                        "require"
    DB_DRIVER:                     "postgres"
    PGRST_DB_SCHEMAS:              "public,storage,graphql_public"
    PGRST_DB_ANON_ROLE:            "anon"
    PGRST_DB_USE_LEGACY_GUCS:      "false"
    PGRST_APP_SETTINGS_JWT_SECRET: "${jwt_secret}"
    PGRST_APP_SETTINGS_JWT_EXP:    "3600"

# ─── Realtime (WebSocket / CDC) ───────────────────────────────────────────────
realtime:
  environment:
    DB_HOST:                "${aurora_host}"
    DB_PORT:                "5432"
    DB_NAME:                "${project_name}"
    DB_USER:                "supabase_realtime_admin"
    DB_SSL:                 "true"
    # "auto" prevents NXDOMAIN errors when Aurora hostname resolves via DNS
    DB_IP_VERSION:          "auto"
    DB_AFTER_CONNECT_QUERY: "SET search_path TO _realtime"
    DB_ENC_KEY:             "${realtime_enc_key}"
    SLOT_NAME:              "supabase_realtime_${project_name}"
    PUBLICATION:            "supabase_realtime"
    PORT:                   "4000"
    FLY_ALLOC_ID:           "fly123"
    FLY_APP_NAME:           "realtime"
    SECRET_KEY_BASE:        "${realtime_secret_key_base}"
    ERL_AFLAGS:             "-proto_dist inet_tcp"
    ENABLE_TAILSCALE:       "false"
    DNS_NODES:              "''"
    APP_NAME:               "realtime"

# ─── Storage API ──────────────────────────────────────────────────────────────
storage:
  environment:
    DB_HOST:            "${aurora_host}"
    DB_PORT:            "5432"
    DB_NAME:            "${project_name}"
    DB_USER:            "supabase_storage_admin"
    DB_SSL:             "require"
    DB_DRIVER:          "postgres"
    STORAGE_BACKEND:    "s3"
    GLOBAL_S3_BUCKET:   "${s3_bucket_name}"
    AWS_DEFAULT_REGION: "${aws_region}"
    TENANT_ID:          "${project_name}"
    FILE_SIZE_LIMIT:    "52428800"
    # No AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY — IRSA handles credentials via pod identity
  serviceAccount:
    create: true
    name:   "supabase-${project_name}-storage"
    annotations:
      eks.amazonaws.com/role-arn: "${storage_irsa_role_arn}"

# ─── Meta (postgres-meta) ─────────────────────────────────────────────────────
meta:
  environment:
    DB_HOST:      "${aurora_host}"
    DB_PORT:      "5432"
    DB_NAME:      "${project_name}"
    DB_USER:      "supabase_admin_user"
    DB_SSL:       "require"
    DB_DRIVER:    "postgres"
    PG_META_PORT: "8080"

# ─── Kong (API Gateway) ───────────────────────────────────────────────────────
kong:
  environment:
    SUPABASE_ANON_KEY:    "${anon_key}"
    SUPABASE_SERVICE_KEY: "${service_key}"
  ingress:
    enabled: true
    className: "alb"
    annotations:
      kubernetes.io/ingress.class: "alb"
      alb.ingress.kubernetes.io/scheme: "internet-facing"
      alb.ingress.kubernetes.io/target-type: "ip"
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    hosts:
      - host: "${project_name}.example.com"
        paths:
          - path: /
            pathType: Prefix

# ─── Analytics (Logflare) ─────────────────────────────────────────────────────
# Disabled: requires Logflare API key and BigQuery or separate Postgres backend
analytics:
  enabled: false

# ─── Vector (log pipeline) ────────────────────────────────────────────────────
# Disabled together with analytics
vector:
  enabled: false

# ─── MinIO (S3-compatible storage) ───────────────────────────────────────────
# Disabled: using AWS S3 directly via IRSA
minio:
  enabled: false

# ─── ImgProxy ────────────────────────────────────────────────────────────────
imgproxy:
  enabled: true
