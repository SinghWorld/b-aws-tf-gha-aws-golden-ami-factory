data "aws_partition" "current" {}

locals {
  # Build a map of AMI IDs by OS key from the SSM parameters
  ami_ids = {
    for os_key in var.os_keys :
    os_key => data.aws_ssm_parameter.ami[os_key].value
  }
}

# Data source to read AMI IDs from SSM parameters
data "aws_ssm_parameter" "ami" {
  for_each = toset(var.os_keys)
  name     = "${var.ssm_parameter_prefix}/${each.key}/latest"
}

# Share each AMI with target accounts
resource "aws_ec2_ami_launch_permission" "share" {
  for_each = { for os_key, ami_id in local.ami_ids : os_key => ami_id }

  image_id = each.value
  account_id = var.target_account_ids
}

# Optional: Create SSM parameters in target accounts (requires cross-account role)
# This would need to be run in each target account or via a provider alias
# For now, we just share the AMI; target accounts can create their own SSM parameters
# from the shared AMI ID.