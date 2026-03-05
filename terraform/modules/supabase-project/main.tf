resource "helm_release" "supabase" {
  name             = "supabase-${var.project_name}"
  repository       = "https://supabase-community.github.io/supabase-kubernetes"
  chart            = "supabase"
  version          = "0.5.0"
  namespace = "supabase-${var.project_name}"
  wait      = true
  timeout          = 600

  values = [templatefile("${path.module}/values.yaml.tpl", {
    project_name             = var.project_name
    aws_region               = var.aws_region
    anon_key                 = var.anon_key
    service_key              = var.service_key
    jwt_secret               = var.jwt_secret
    authenticator_password   = var.authenticator_password
    studio_password          = var.studio_password
    realtime_enc_key         = var.realtime_enc_key
    realtime_secret_key_base = var.realtime_secret_key_base
    storage_irsa_role_arn    = aws_iam_role.storage_irsa.arn
    s3_bucket_name           = aws_s3_bucket.storage.id
    external_url             = var.external_url
    vault_enc_key            = var.vault_enc_key
    meta_crypto_key          = var.meta_crypto_key
    logflare_public_token    = var.logflare_public_token
    logflare_private_token   = var.logflare_private_token
  })]

  depends_on = [
    aws_iam_role.storage_irsa,
    aws_s3_bucket.storage,
    kubernetes_persistent_volume_claim.edge_functions,
  ]
}
