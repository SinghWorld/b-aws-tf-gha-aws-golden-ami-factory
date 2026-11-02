# =============================================================================
# Cross-Account AMI Sharing Configuration - DEPRECATED
# =============================================================================
# ⚠️ THIS ENVIRONMENT IS NO LONGER NEEDED
#
# AMI sharing is now handled natively by AWS Image Builder's distribution
# configuration in the prod environment. No separate Terraform apply required.
#
# The `golden_image` module's `aws_imagebuilder_distribution_configuration`
# automatically shares AMIs and creates SSM parameters in target accounts
# during pipeline execution.
#
# Configuration is in: environments/prod/variables.tf -> target_account_ids
#
# =============================================================================

module "ami_sharing" {
  source = "../../modules/ami_sharing"

  os_keys              = var.enabled_os
  ssm_parameter_prefix = var.ssm_parameter_prefix
  target_account_ids   = var.target_account_ids
}