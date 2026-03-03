locals {
  init_script = templatefile("${path.module}/scripts/init_db.sh.tpl", {
    aurora_host            = var.aurora_host
    project_name           = var.project_name
    master_secret_arn      = var.master_secret_arn
    aws_region             = var.aws_region
    authenticator_password = var.authenticator_password
    auth_password          = var.auth_password
    storage_password       = var.storage_password
    realtime_password      = var.realtime_password
    admin_password         = var.admin_password
  })

  # Generated script path — added to .gitignore
  script_path = "${path.module}/.generated/init_${var.project_name}.sh"
}

# Write the rendered init script to a file, then execute it.
#
# IMPORTANT: The Terraform host must have:
#   1. psql installed and on PATH
#   2. aws CLI installed with credentials to read Secrets Manager
#   3. Network access to the Aurora endpoint (VPN, bastion, or Cloud9 inside the VPC)
#
# The script file is written to .generated/ (gitignored) and deleted after apply
# by the cleanup null_resource below.

resource "local_file" "init_script" {
  content         = local.init_script
  filename        = local.script_path
  file_permission = "0700"
}

resource "null_resource" "db_init" {
  triggers = {
    project     = var.project_name
    script_hash = sha256(local.init_script)
    # Re-run if Aurora was rebooted (new cluster)
    reboot_id   = var.reboot_complete_trigger
  }

  provisioner "local-exec" {
    command     = "bash ${local_file.init_script.filename}"
    interpreter = ["bash", "-c"]
  }

  depends_on = [local_file.init_script]
}

# Remove the generated script file after successful db_init execution
resource "null_resource" "cleanup_script" {
  triggers = {
    script_path = local.script_path
    db_init_id  = null_resource.db_init.id
  }

  provisioner "local-exec" {
    command    = "rm -f '${local.script_path}'"
    on_failure = continue
  }

  depends_on = [null_resource.db_init]
}
