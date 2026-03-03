-- postgres user for developers
CREATE USER postgres WITH LOGIN;
GRANT rds_replication TO postgres;  

-- Cria o banco de dados isolado
CREATE DATABASE projeto_a;

-- Cria o usuário específico para este projeto
CREATE USER supabase_admin_pj_a WITH LOGIN PASSWORD '44+-|srT5:ox';

-- No Aurora, rds_superuser é o cargo mais alto que você pode dar
GRANT rds_superuser TO supabase_admin_pj_a;