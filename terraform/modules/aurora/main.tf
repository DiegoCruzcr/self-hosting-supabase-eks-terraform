# ─── Security Group: Aurora ──────────────────────────────────────────────────

resource "aws_security_group" "aurora" {
  name        = "supabase-aurora-sg"
  description = "Allow PostgreSQL access from EKS nodes"
  vpc_id      = var.vpc_id

  # ingress {
  #   description     = "PostgreSQL from EKS nodes"
  #   from_port       = 5432
  #   to_port         = 5432
  #   protocol        = "tcp"
  #   security_groups = [var.node_security_group_id]
  # }

  ingress {
    description     = "PostgreSQL public access (dev only)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = var.publicly_accessible ? var.allowed_cidr_blocks : []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "supabase-aurora-sg"
  }
}

# Open port 5432 to the internet when publicly_accessible = true.
# Use var.allowed_cidr_blocks to restrict access to your own IP.
resource "aws_security_group_rule" "aurora_public_access" {
  count = var.publicly_accessible ? 1 : 0

  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.aurora.id
  description       = "PostgreSQL public access (dev only)"
}

# ─── Cluster Parameter Group ──────────────────────────────────────────────────

resource "aws_rds_cluster_parameter_group" "supabase" {
  name        = "supabase-aurora-pg15"
  family      = "aurora-postgresql15"
  description = "Supabase Aurora PostgreSQL 15 parameter group"

  # Required for Realtime CDC via WAL — needs reboot
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # parameter {
  #   name         = "wal_level"
  #   value        = "logical"
  #   apply_method = "pending-reboot"
  # }

  # pg_cron and pg_stat_statements preloaded — needs reboot
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pg_cron,pg_tle,pgaudit"
    apply_method = "pending-reboot"
  }

  # These take effect pending-rebootly
  parameter {
    name         = "max_replication_slots"
    value        = "10"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = "10"
    apply_method = "pending-reboot"
  }

  # pg_cron only runs on one database; use first project's DB
  parameter {
    name         = "cron.database_name"
    value        = var.first_project_name
    apply_method = "pending-reboot"
  }
}

# ─── Aurora Serverless v2 Cluster ─────────────────────────────────────────────

resource "aws_rds_cluster" "supabase" {
  cluster_identifier              = "supabase-aurora"
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned" # Serverless v2 uses provisioned + scaling config
  engine_version                  = "15.12" # Aurora PostgreSQL 15.12 is the latest as of June 2024
  master_username                 = "supabase_master"
  manage_master_user_password     = true # Stores password in Secrets Manager automatically
  db_subnet_group_name            = var.db_subnet_group_name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.supabase.name
  skip_final_snapshot             = true  # dev only
  deletion_protection             = false # dev only

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  tags = {
    Name = "supabase-aurora"
  }
}

# ─── Aurora Instance ──────────────────────────────────────────────────────────

resource "aws_rds_cluster_instance" "supabase" {
  count = 1

  identifier          = "supabase-aurora-instance-1"
  cluster_identifier  = aws_rds_cluster.supabase.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.supabase.engine
  engine_version      = aws_rds_cluster.supabase.engine_version
  publicly_accessible = var.publicly_accessible

  tags = {
    Name = "supabase-aurora-instance-1"
  }
}

# ─── Aurora Reboot (activates pending-reboot parameters) ──────────────────────
#
# rds.logical_replication and wal_level require a reboot to take effect.
# These are mandatory for the Realtime service (CDC via WAL).
# This null_resource fires once when the cluster is first created.

resource "null_resource" "aurora_reboot" {
  depends_on = [aws_rds_cluster_instance.supabase]

  triggers = {
    cluster_id            = aws_rds_cluster.supabase.id
    parameter_group_name  = aws_rds_cluster_parameter_group.supabase.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Rebooting Aurora cluster to activate logical replication parameters..."
      aws rds reboot-db-cluster \
        --db-cluster-identifier ${aws_rds_cluster.supabase.id} \
        --region ${var.aws_region}

      echo "Waiting for Aurora cluster to be available after reboot..."
      aws rds wait db-cluster-available \
        --db-cluster-identifier ${aws_rds_cluster.supabase.id} \
        --region ${var.aws_region}

      echo "Aurora cluster is available. Logical replication parameters are now active."
    EOT
  }
}
