data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_kms_alias" "ebs" {
  count = var.ebs_encrypted ? 1 : 0
  name  = var.ebs_kms_key_alias
}

locals {
  name_prefix    = var.project
  ami_date_token = coalesce(var.ami_date_token, formatdate(var.ami_date_format, plantimestamp()))

  common_tags = merge(var.extra_tags, {
    CostCentre  = "579087"
    CreatedBy   = "DL-TechInfraCloud@singhworld.com"
    Environment = "Production"
    DeployedBy  = "IAC using Terraform"
    Owner       = "DL-TechInfraCloud@singhworld.com"
    ProtectedBy = "Tech-Infra-Cloud@singhworld.com"
  })

  # Amazon managed resources use account "aws" and x.x.x to track the newest version.
  # AWS managed components (CIS, STIG, etc.) are only available in us-east-1, so we use a fixed region.
  jq_prefix = "arn:${data.aws_partition.current.partition}:imagebuilder:${data.aws_region.current.region}:aws"
  # For AWS managed components, always use us-east-1 where they are published
  aws_managed_prefix = "arn:${data.aws_partition.current.partition}:imagebuilder:us-east-1:aws"

  # Recipes select the latest available custom component; build logs show the resolved version.
  latest_component_arns = {
    for key, arn in module.components.arns :
    key => replace(arn, "//[0-9]+\\.[0-9]+\\.[0-9]+(/[0-9]+)?$/", "/x.x.x")
  }

  # LEGACY: OS catalog for backward compatibility with enabled_os variable
  # New deployments should use recipe_registry module with enabled_recipes
  os_catalog = {
    "rhel-8"       = { family = "linux", display = "RHEL 8", ami_os_code = "rhel8", parent = "red-hat-enterprise-linux-8-x86", volume_gb = 100 }
    "rhel-9"       = { family = "linux", display = "RHEL 9", ami_os_code = "rhel9", parent = "red-hat-enterprise-linux-9-x86", volume_gb = 100 }
    "rhel-10"      = { family = "linux", display = "RHEL 10", ami_os_code = "rhel10", parent = "red-hat-enterprise-linux-10-x86", volume_gb = 100 }
    "windows-2022" = { family = "windows", display = "Windows Server 2022", ami_os_code = "win2022", parent = "windows-server-2022-english-full-base-x86", volume_gb = 100 }
    "windows-2025" = { family = "windows", display = "Windows Server 2025", ami_os_code = "win2025", parent = "windows-server-2025-english-full-base-x86", volume_gb = 50 }
  }

  enabled_os = { for k, v in local.os_catalog : k => v if contains(var.enabled_os, k) }

  # LEGACY: Component chains for backward compatibility
  # New deployments use recipe_registry module with declarative YAML recipes
  component_chain = {
    windows = [
      "${local.aws_managed_prefix}:component/update-windows/x.x.x",
      "${local.aws_managed_prefix}:component/aws-cli-version-2-windows/x.x.x",
      local.latest_component_arns["windows-ssm-agent"],
      "${local.aws_managed_prefix}:component/cis-build-windows/x.x.x",
      module.components.arns["windows-hardening"],
      module.components.arns["windows-validate"],
      "${local.aws_managed_prefix}:component/amazon-cloudwatch-agent-windows/x.x.x",
      "${local.aws_managed_prefix}:component/simple-boot-test-windows/x.x.x",
    ]
    linux = [
      "${local.aws_managed_prefix}:component/update-linux/x.x.x",
      "${local.aws_managed_prefix}:component/aws-cli-version-2-linux/x.x.x",
      module.components.arns["linux-ssm-agent"],
      "${local.aws_managed_prefix}:component/cis-build-linux/x.x.x",
      module.components.arns["linux-hardening"],
      module.components.arns["linux-validate"],
      "${local.aws_managed_prefix}:component/amazon-cloudwatch-agent-linux/x.x.x",
      "${local.aws_managed_prefix}:component/simple-boot-test-linux/x.x.x",
    ]
  }
}
