# ─── Deployment enablement ────────────────────────────────────────────────────
deployment:
  db:
    enabled: true
  analytics:
    enabled: true
  vector:
    enabled: true
  minio:
    enabled: false

# ─── Persistence (EBS via EBS CSI driver installed in EKS module) ─────────────
persistence:
  db:
    enabled: true
    storageClassName: "gp2"
    size: "20Gi"

# ─── Secrets ──────────────────────────────────────────────────────────────────
secret:
  jwt:
    anonKey:    "${anon_key}"
    serviceKey: "${service_key}"
    secret:     "${jwt_secret}"
  db:
    password: "${authenticator_password}"
    database: "postgres"
  dashboard:
    username: "supabase"
    password: "${studio_password}"
  realtime:
    secretKeyBase: "${realtime_secret_key_base}"
  meta:
    cryptoKey: "${meta_crypto_key}"
  analytics:
    publicAccessToken:  "${logflare_public_token}"
    privateAccessToken: "${logflare_private_token}"

# ─── Service Accounts (IRSA for Storage) ──────────────────────────────────────
serviceAccount:
  storage:
    create: true
    name:   "supabase-${project_name}-storage"
    annotations:
      eks.amazonaws.com/role-arn: "${storage_irsa_role_arn}"

# ─── Environment variables per service ───────────────────────────────────────
# Chart reads from .Values.environment.<service> — NOT <service>.environment
environment:
  studio:
    SUPABASE_PUBLIC_URL:             "${external_url}"
    DEFAULT_ORGANIZATION_NAME:       "${project_name}"
    DEFAULT_PROJECT_NAME:            "${project_name}"
    NEXT_PUBLIC_ENABLE_LOGS:         "true"
    LOGFLARE_URL:                    "http://supabase-${project_name}-analytics:4000"
    NEXT_ANALYTICS_BACKEND_PROVIDER: "postgres"

  auth:
    API_EXTERNAL_URL:              "${external_url}"
    GOTRUE_SITE_URL:               "${external_url}"
    GOTRUE_URI_ALLOW_LIST:         "*"
    GOTRUE_DISABLE_SIGNUP:         "false"
    GOTRUE_JWT_DEFAULT_GROUP_NAME: "authenticated"
    GOTRUE_JWT_ADMIN_ROLES:        "service_role"
    GOTRUE_JWT_AUD:                "authenticated"
    GOTRUE_JWT_EXP:                "3600"
    GOTRUE_MAILER_AUTOCONFIRM:     "true"
    GOTRUE_EXTERNAL_EMAIL_ENABLED: "true"
    DB_PORT:                       "5432"
    DB_USER:                       "supabase_auth_admin"
    DB_SSL:                        "disable"
    DB_DRIVER:                     "postgres"

  rest:
    DB_PORT:                    "5432"
    DB_USER:                    "authenticator"
    DB_SSL:                     "disable"
    DB_DRIVER:                  "postgres"
    PGRST_DB_SCHEMAS:           "public,storage,graphql_public"
    PGRST_DB_ANON_ROLE:         "anon"
    PGRST_DB_USE_LEGACY_GUCS:   "false"
    PGRST_APP_SETTINGS_JWT_EXP: "3600"

  realtime:
    DB_USER:                "supabase_admin"
    DB_PORT:                "5432"
    DB_SSL:                 "false"
    DB_AFTER_CONNECT_QUERY: "SET search_path TO _realtime"
    SLOT_NAME:              "supabase_realtime"
    PUBLICATION:            "supabase_realtime"
    PORT:                   "4000"
    FLY_ALLOC_ID:           "fly123"
    FLY_APP_NAME:           "realtime"
    ERL_AFLAGS:             "-proto_dist inet_tcp"
    ENABLE_TAILSCALE:       "false"
    DNS_NODES:              "''"
    APP_NAME:               "realtime"
    DB_IP_VERSION:          "ipv4"
    DB_ENC_KEY:             "${realtime_enc_key}"

  storage:
    DB_PORT:            "5432"
    DB_USER:            "supabase_storage_admin"
    DB_SSL:             "disable"
    DB_DRIVER:          "postgres"
    STORAGE_BACKEND:    "s3"
    GLOBAL_S3_BUCKET:   "${s3_bucket_name}"
    AWS_DEFAULT_REGION: "${aws_region}"
    TENANT_ID:          "${project_name}"
    FILE_SIZE_LIMIT:    "52428800"

  meta:
    DB_PORT:      "5432"
    DB_USER:      "supabase_admin"
    DB_SSL:       "disable"
    DB_DRIVER:    "postgres"
    PG_META_PORT: "8080"

  analytics:
    LOGFLARE_NODE_HOST:             "127.0.0.1"
    DB_USERNAME:                    "supabase_admin"
    DB_DATABASE:                    "_supabase"
    DB_PORT:                        "5432"
    DB_DRIVER:                      "postgresql"
    DB_SCHEMA:                      "_analytics"
    POSTGRES_BACKEND_SCHEMA:        "_analytics"
    LOGFLARE_SINGLE_TENANT:         "true"
    LOGFLARE_SUPABASE_MODE:         "true"
    LOGFLARE_FEATURE_FLAG_OVERRIDE: "multibackend=true"
    POSTGRES_BACKEND_URL:           "postgresql://supabase_admin:${authenticator_password}@supabase-${project_name}-db:5432/_supabase"
    LOGFLARE_LOG_LEVEL:             "warn"

  # Note: SUPABASE_ANON_KEY and SUPABASE_SERVICE_KEY are injected by the chart
  # from secret.jwt via secretKeyRef — do NOT set them here (would cause duplicate conflict)
  kong: {}

  db:
    VAULT_ENC_KEY: "${vault_enc_key}"

# ─── Ingress (top-level — read by templates/kong/ingress.yaml) ────────────────
ingress:
  enabled: true
  className: "alb"
  annotations:
    kubernetes.io/ingress.class: "alb"
    alb.ingress.kubernetes.io/scheme: "internet-facing"
    alb.ingress.kubernetes.io/target-type: "ip"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
  hosts:
    - host: ""
      paths:
        - path: /
          pathType: Prefix
