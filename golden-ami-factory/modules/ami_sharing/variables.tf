variable "os_keys" {
  description = "List of OS keys (e.g., rhel-8, rhel-9, windows-2022) to share AMIs for"
  type        = list(string)
}

variable "ssm_parameter_prefix" {
  description = "SSM Parameter Store prefix where the AMI IDs are stored"
  type        = string
  default     = "/golden-ami"
}

variable "target_account_ids" {
  description = "List of AWS account IDs to share the AMIs with"
  type        = list(string)
}