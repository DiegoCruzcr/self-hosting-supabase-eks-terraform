CREATE EXTENSION IF NOT EXISTS pg_tle;
-- GRANT pgtle_admin TO supabase_admin;
GRANT pgtle_admin TO postgres;
GRANT pgtle_admin TO supabase_master;
GRANT pgtle_admin TO supabase_admin_pj_a; -- For each project-specific user, we need to grant pgtle_admin so they can install pgjwt and other extensions that depend on pg_tle