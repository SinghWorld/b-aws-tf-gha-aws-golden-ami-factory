locals {
  definitions = {
    windows-ssm-agent        = { platform = "Windows", file = "windows-ssm-agent.yml", description = "Checks and reports the Amazon SSM Agent version on Windows" }
    windows-hardening        = { platform = "Windows", file = "windows-hardening.yml", description = "Extra Windows hardening after the STIG component" }
    windows-validate         = { platform = "Windows", file = "windows-validate.yml", description = "Windows baseline validation tests" }
    windows-cloudwatch-agent = { platform = "Windows", file = "windows-cloudwatch-agent.yml", description = "Installs and configures CloudWatch Agent on Windows" }
    linux-ssm-agent          = { platform = "Linux", file = "linux-ssm-agent.yml", description = "Installs or upgrades the Amazon SSM Agent on RHEL" }
    linux-hardening          = { platform = "Linux", file = "linux-hardening.yml", description = "Extra RHEL hardening after the STIG component" }
    linux-validate           = { platform = "Linux", file = "linux-validate.yml", description = "RHEL baseline validation tests" }
    linux-cloudwatch-agent   = { platform = "Linux", file = "linux-cloudwatch-agent.yml", description = "Installs and configures CloudWatch Agent on RHEL" }
  }
}

# Component documents are immutable per name+version. A content hash in the name
# means any edit to a YAML file produces a new component automatically, with no
# manual version bump, and create_before_destroy keeps the recipe attachable.
resource "aws_imagebuilder_component" "this" {
  for_each = local.definitions

  name               = "${var.name_prefix}-${each.key}-${substr(filesha256("${path.module}/files/${each.value.file}"), 0, 8)}"
  version            = "1.0.0"
  platform           = each.value.platform
  description        = each.value.description
  change_description = "Managed by Terraform"
  data               = file("${path.module}/files/${each.value.file}")
  tags               = var.tags

  lifecycle {
    create_before_destroy = true
  }
}
