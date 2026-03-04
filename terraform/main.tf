module "vpc" {
  source = "./modules/vpc"

  aws_region   = var.aws_region
  cluster_name = var.cluster_name
}

# module "eks" {
#   source = "./modules/eks"

#   aws_region         = var.aws_region
#   cluster_name       = var.cluster_name
#   vpc_id             = module.vpc.vpc_id
#   private_subnet_ids = module.vpc.private_subnet_ids
#   public_subnet_ids  = module.vpc.public_subnet_ids
#   node_instance_type = var.eks_node_instance_type
#   node_desired_size  = var.eks_node_desired_size
#   node_min_size      = var.eks_node_min_size
#   node_max_size      = var.eks_node_max_size
# }

# Aurora removed — using supabase/postgres pod per project instead

# module "aurora_db_init" {
#   source   = "./modules/aurora-db-init"
#   for_each = { for p in var.projects : p.name => p }

#   aws_region               = var.aws_region
#   aurora_host              = module.aurora.cluster_endpoint
#   project_name             = each.value.name
#   master_secret_arn        = module.aurora.master_secret_arn
#   authenticator_password   = each.value.authenticator_password
#   auth_password            = each.value.auth_password
#   storage_password         = each.value.storage_password
#   realtime_password        = each.value.realtime_password
#   admin_password           = each.value.admin_password
#   reboot_complete_trigger  = module.aurora.reboot_id

#   depends_on = [module.aurora]
# }

# module "supabase_project" {
#   source   = "./modules/supabase-project"
#   for_each = { for p in var.projects : p.name => p }

#   aws_region               = var.aws_region
#   project_name             = each.value.name
#   aurora_host              = module.aurora.cluster_endpoint
#   jwt_secret               = each.value.jwt_secret
#   anon_key                 = each.value.anon_key
#   service_key              = each.value.service_key
#   authenticator_password   = each.value.authenticator_password
#   studio_password          = each.value.studio_password
#   realtime_enc_key         = each.value.realtime_enc_key
#   realtime_secret_key_base = each.value.realtime_secret_key_base
#   cluster_oidc_provider_arn = module.eks.cluster_oidc_provider_arn
#   cluster_oidc_issuer_url  = module.eks.cluster_oidc_issuer_url

#   depends_on = [module.aurora_db_init, module.eks]
# }
