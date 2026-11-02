output "shared_ami_ids" {
  description = "Map of OS keys to shared AMI IDs"
  value       = { for os_key, ami_id in data.aws_ssm_parameter.ami : os_key => ami_id.value }
}

output "target_accounts" {
  description = "List of AWS account IDs the AMIs were shared with"
  value       = var.target_account_ids
}