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

# ─── Supabase Project (per project) ──────────────────────────────────────────
module "supabase_project" {
  source   = "../../modules/supabase-project"
  for_each = { for p in var.projects : p.name => p }

  aws_region                = var.aws_region
  project_name              = each.value.name
  jwt_secret                = each.value.jwt_secret
  anon_key                  = each.value.anon_key
  service_key               = each.value.service_key
  authenticator_password    = each.value.authenticator_password
  studio_password           = each.value.studio_password
  realtime_enc_key          = each.value.realtime_enc_key
  realtime_secret_key_base  = each.value.realtime_secret_key_base
  external_url              = each.value.external_url
  vault_enc_key             = each.value.vault_enc_key
  meta_crypto_key           = each.value.meta_crypto_key
  logflare_public_token     = each.value.logflare_public_token
  logflare_private_token    = each.value.logflare_private_token
  cluster_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  efs_file_system_id        = module.eks.efs_file_system_id

  depends_on = [module.eks]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "project_namespaces" {
  value = [for p in var.projects : "supabase-${p.name}"]
}
