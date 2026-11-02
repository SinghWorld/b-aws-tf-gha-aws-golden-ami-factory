# =============================================================================
# Cross-Account AMI Sharing Configuration
# =============================================================================
# This configuration shares the built Golden AMIs with target AWS accounts.
# Deploy this in the SOURCE account (where AMIs are built) after the golden_image
# pipeline has successfully created AMIs and stored their IDs in SSM parameters.
#
# Usage:
#   terraform init
#   terraform apply -var="target_account_ids=[\"123456789012\", \"234567890123\"]"
# =============================================================================

module "ami_sharing" {
  source = "../../modules/ami_sharing"

  os_keys              = var.enabled_os
  ssm_parameter_prefix = var.ssm_parameter_prefix
  target_account_ids   = var.target_account_ids
}