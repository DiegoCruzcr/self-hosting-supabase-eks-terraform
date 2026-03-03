terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── Data source: EKS auth token ──────────────────────────────────────────────
# Fetches a short-lived token to authenticate with the EKS Kubernetes API.
data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

# ─── Kubernetes + Helm providers ─────────────────────────────────────────────
# These reference module.eks outputs. On first apply, the providers are lazily
# evaluated — they are only needed when helm_release resources are created,
# which happens after the EKS cluster is available.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# ─── VPC ──────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  aws_region   = var.aws_region
  cluster_name = var.cluster_name
}

# ─── EKS ──────────────────────────────────────────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  aws_region         = var.aws_region
  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  node_instance_type = var.eks_node_instance_type
  node_desired_size  = var.eks_node_desired_size
  node_min_size      = var.eks_node_min_size
  node_max_size      = var.eks_node_max_size
}

# ─── Aurora ───────────────────────────────────────────────────────────────────
module "aurora" {
  source = "../../modules/aurora"

  aws_region             = var.aws_region
  vpc_id                 = module.vpc.vpc_id
  # Use public subnet group so the instance can receive a public IP
  db_subnet_group_name   = module.vpc.public_db_subnet_group_name
  node_security_group_id = module.eks.node_security_group_id
  aurora_engine_version  = var.aurora_engine_version
  aurora_min_capacity    = var.aurora_min_capacity
  aurora_max_capacity    = var.aurora_max_capacity
  publicly_accessible    = true
  # Restrict to your own IP for security: ["203.0.113.42/32"]
  # Leave as 0.0.0.0/0 only for dev; never in production
  allowed_cidr_blocks    = ["0.0.0.0/0"]
  first_project_name     = var.projects[0].name
}

# ─── Aurora DB Init (per project) ────────────────────────────────────────────
module "aurora_db_init" {
  source   = "../../modules/aurora-db-init"
  for_each = { for p in var.projects : p.name => p }

  aws_region               = var.aws_region
  aurora_host              = module.aurora.cluster_endpoint
  project_name             = each.value.name
  master_secret_arn        = module.aurora.master_secret_arn
  authenticator_password   = each.value.authenticator_password
  auth_password            = each.value.auth_password
  storage_password         = each.value.storage_password
  realtime_password        = each.value.realtime_password
  admin_password           = each.value.admin_password
  reboot_complete_trigger  = module.aurora.reboot_id

  depends_on = [module.aurora]
}

# ─── Supabase Project (per project) ──────────────────────────────────────────
module "supabase_project" {
  source   = "../../modules/supabase-project"
  for_each = { for p in var.projects : p.name => p }

  aws_region                = var.aws_region
  project_name              = each.value.name
  aurora_host               = module.aurora.cluster_endpoint
  jwt_secret                = each.value.jwt_secret
  anon_key                  = each.value.anon_key
  service_key               = each.value.service_key
  authenticator_password    = each.value.authenticator_password
  studio_password           = each.value.studio_password
  realtime_enc_key          = each.value.realtime_enc_key
  realtime_secret_key_base  = each.value.realtime_secret_key_base
  cluster_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url

  depends_on = [module.aurora_db_init, module.eks]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "aurora_cluster_endpoint" {
  value = module.aurora.cluster_endpoint
}

output "aurora_master_secret_arn" {
  value     = module.aurora.master_secret_arn
  sensitive = false
}

output "project_namespaces" {
  value = [for p in var.projects : "supabase-${p.name}"]
}
