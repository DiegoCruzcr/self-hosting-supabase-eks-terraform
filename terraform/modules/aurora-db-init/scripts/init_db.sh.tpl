#!/bin/bash
# Aurora DB initialization script for project: ${project_name}
# Run once per project after Aurora cluster reboot.
# Requires: psql, aws CLI, network access to Aurora endpoint.
# PGPASSWORD is set by the calling null_resource from Secrets Manager.
set -euo pipefail

AURORA_HOST="${aurora_host}"
PROJECT="${project_name}"
AURORA_PORT="5432"
MASTER_USER="supabase_master"
MASTER_PASSWORD='#d|hLN_|)7:L0At:XUR$58hX~fAS'

# Fetch master password from Secrets Manager
# MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
#   --secret-id "${master_secret_arn}" \
#   --region "${aws_region}" \
#   --query "SecretString" \
#   --output text | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

export PGPASSWORD="$MASTER_PASSWORD"

PSQL="psql -h $AURORA_HOST -p $AURORA_PORT -U $MASTER_USER -v ON_ERROR_STOP=1"

echo "=== Step 1: Create database '$PROJECT' ==="
$PSQL -d postgres -c "CREATE DATABASE \"$PROJECT\";" || echo "Database may already exist, continuing..."

echo "=== Step 2: Create roles in '$PROJECT' ==="
$PSQL -d "$PROJECT" <<'EOSQL'
-- Non-login roles
CREATE ROLE anon           NOLOGIN NOINHERIT;
CREATE ROLE authenticated  NOLOGIN NOINHERIT;
CREATE ROLE service_role   NOLOGIN NOINHERIT BYPASSRLS;
CREATE ROLE supabase_admin NOLOGIN INHERIT CREATEDB CREATEROLE;

-- Authenticator: PostgREST uses this to SET ROLE per request
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD '${authenticator_password}';
GRANT anon           TO authenticator;
GRANT authenticated  TO authenticator;
GRANT service_role   TO authenticator;
GRANT supabase_admin TO authenticator;

-- GoTrue (Auth service)
CREATE ROLE supabase_auth_admin NOINHERIT LOGIN CREATEDB PASSWORD '${auth_password}';

-- Storage API
CREATE ROLE supabase_storage_admin NOINHERIT LOGIN CREATEDB PASSWORD '${storage_password}';

-- Realtime service
-- AURORA-SPECIFIC: use rds_replication role instead of REPLICATION attribute
CREATE ROLE supabase_realtime_admin NOINHERIT LOGIN PASSWORD '${realtime_password}';
GRANT rds_replication TO supabase_realtime_admin;

-- General admin for Supavisor, Studio, pg-meta
CREATE ROLE supabase_admin_user LOGIN PASSWORD '${admin_password}' CREATEDB CREATEROLE;
GRANT rds_superuser TO supabase_admin_user;
EOSQL

echo "=== Step 3: Enable extensions in '$PROJECT' ==="
$PSQL -d "$PROJECT" <<'EOSQL'
-- Create extensions schema first
CREATE SCHEMA IF NOT EXISTS extensions;

-- Enable supported extensions
-- NOTE: pg_graphql, pg_net, pgjwt, pgsodium are NOT available on Aurora
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"        WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pgcrypto"          WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "vector"            WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pg_tle";
CREATE EXTENSION IF NOT EXISTS "pg_cron";
EOSQL

echo "=== Step 4: Create schemas in '$PROJECT' ==="
$PSQL -d "$PROJECT" <<'EOSQL'
-- AURORA-SAFE: use ALTER SCHEMA ... OWNER TO instead of CREATE SCHEMA AUTHORIZATION
CREATE SCHEMA IF NOT EXISTS auth;
ALTER  SCHEMA auth     OWNER TO supabase_auth_admin;

CREATE SCHEMA IF NOT EXISTS storage;
ALTER  SCHEMA storage  OWNER TO supabase_storage_admin;

CREATE SCHEMA IF NOT EXISTS realtime;
ALTER  SCHEMA realtime OWNER TO supabase_realtime_admin;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS _analytics;
CREATE SCHEMA IF NOT EXISTS graphql_public; -- kept empty; pg_graphql is not available on Aurora
EOSQL

echo "=== Step 5: Create logical replication publication in '$PROJECT' ==="
$PSQL -d "$PROJECT" -c "CREATE PUBLICATION supabase_realtime FOR ALL TABLES;" \
  || echo "Publication may already exist, continuing..."

echo "=== Step 6: Grant permissions in '$PROJECT' ==="
$PSQL -d "$PROJECT" <<'EOSQL'
GRANT USAGE ON SCHEMA public, extensions TO authenticator, anon, authenticated, service_role;
GRANT ALL   ON SCHEMA auth               TO supabase_auth_admin;
GRANT ALL   ON SCHEMA storage            TO supabase_storage_admin;
GRANT ALL   ON SCHEMA realtime           TO supabase_realtime_admin;

-- PostgREST needs to inspect auth schema metadata
GRANT USAGE ON SCHEMA auth TO authenticator;

-- Allow extensions schema access
GRANT USAGE ON SCHEMA extensions TO authenticator, anon, authenticated, service_role;
EOSQL

echo "=== DB initialization complete for project '$PROJECT' ==="
