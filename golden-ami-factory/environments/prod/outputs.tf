data "aws_caller_identity" "deployment" {}

output "deployment_target" {
  description = "Configured AWS account and region Terraform deploys to, including the account ID verified from the provider authentication."
  value = {
    name                = var.deployments[var.deployment_name].account_name
    account_id          = var.deployments[var.deployment_name].account_id
    verified_account_id = data.aws_caller_identity.deployment.account_id
    region              = var.deployments[var.deployment_name].aws_region
  }

  precondition {
    condition     = data.aws_caller_identity.deployment.account_id == var.deployments[var.deployment_name].account_id
    error_message = "The AWS provider is authenticated to account ${data.aws_caller_identity.deployment.account_id}, but deployment_name selects account ${var.deployments[var.deployment_name].account_id}. Terraform will not proceed."
  }
}

output "pipeline_arns" {
  description = "Pipeline ARN per OS. The monthly workflow starts each one."
  value       = { for k, m in module.golden_image : k => m.pipeline_arn }
}

output "ssm_parameters" {
  description = "Parameter that always holds the latest AMI ID per OS."
  value       = { for k, m in module.golden_image : k => m.ssm_parameter_name }
}

output "ami_name_templates" {
  value = { for k, m in module.golden_image : k => m.ami_name_template }
}

output "kms_key_arn" {
  value = var.ebs_encrypted ? data.aws_kms_alias.ebs[0].target_key_arn : ""
}
