locals {
  oidc_issuer_host = replace(var.cluster_oidc_issuer_url, "https://", "")
  namespace        = "supabase-${var.project_name}"
  sa_name          = "supabase-${var.project_name}-storage"
}

# ─── IRSA Trust Policy for Storage API Service Account ────────────────────────

data "aws_iam_policy_document" "storage_irsa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${local.namespace}:${local.sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "storage_irsa" {
  name               = "supabase-storage-irsa-${var.project_name}"
  assume_role_policy = data.aws_iam_policy_document.storage_irsa_assume.json

  tags = {
    Project = var.project_name
    Purpose = "supabase-storage-irsa"
  }
}

resource "aws_iam_role_policy" "storage_s3" {
  name = "supabase-storage-s3-${var.project_name}"
  role = aws_iam_role.storage_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:CopyObject",
        ]
        Resource = "${aws_s3_bucket.storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = aws_s3_bucket.storage.arn
      }
    ]
  })
}
