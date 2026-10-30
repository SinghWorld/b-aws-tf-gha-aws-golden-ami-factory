provider "aws" {
  region = var.deployments[var.deployment_name].aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.deployments[var.deployment_name].account_id}:role/${var.deployment_role_name}"
    session_name = "terraform-golden-ami"
    external_id  = var.assume_role_external_id
  }

  default_tags {
    tags = local.common_tags
  }
}
