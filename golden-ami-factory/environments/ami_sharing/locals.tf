data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = var.project

  common_tags = merge(var.extra_tags, {
    CostCentre  = "579087"
    CreatedBy   = "DL-TechInfraCloud@singhworld.com"
    Environment = "Production"
    DeployedBy  = "IAC using Terraform"
    Owner       = "DL-TechInfraCloud@singhworld.com"
    ProtectedBy = "Tech-Infra-Cloud@singhworld.com"
  })
}