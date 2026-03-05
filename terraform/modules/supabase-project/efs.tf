# ─── Namespace (explicit — must exist before PVC is created) ──────────────────
# Replaces create_namespace = true in helm_release so Terraform controls ordering.

resource "kubernetes_namespace" "supabase" {
  metadata {
    name = "supabase-${var.project_name}"
  }
}

# ─── EFS Access Point (per project — isolated root directory) ─────────────────
# Each project gets its own directory on the shared EFS file system.
# supabase-alpha → /alpha/functions, supabase-beta → /beta/functions, etc.

resource "aws_efs_access_point" "functions" {
  file_system_id = var.efs_file_system_id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/${var.project_name}/functions"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name    = "supabase-${var.project_name}-functions"
    Project = var.project_name
  }
}

# ─── Persistent Volume (static provisioning bound to the access point) ────────

resource "kubernetes_persistent_volume" "edge_functions" {
  metadata {
    name = "supabase-${var.project_name}-edge-functions-pv"
  }

  spec {
    capacity                         = { storage = "5Gi" }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "efs-sc"

    persistent_volume_source {
      csi {
        driver = "efs.csi.aws.com"
        # fsId::apId — ties this PV to the project-specific access point
        volume_handle = "${var.efs_file_system_id}::${aws_efs_access_point.functions.id}"
      }
    }
  }
}

# ─── Persistent Volume Claim (chart references this via existingClaim) ─────────

resource "kubernetes_persistent_volume_claim" "edge_functions" {
  metadata {
    name      = "supabase-${var.project_name}-edge-functions"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "efs-sc"
    volume_name        = kubernetes_persistent_volume.edge_functions.metadata[0].name

    resources {
      requests = { storage = "5Gi" }
    }
  }
}
