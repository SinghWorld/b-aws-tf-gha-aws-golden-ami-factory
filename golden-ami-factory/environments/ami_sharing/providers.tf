provider "aws" {
  region = var.deployments[var.deployment_name].aws_region

  default_tags {
    tags = local.common_tags
  }
}