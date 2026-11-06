variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the Image Builder build instances."
  type        = string
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}

variable "ssm_parameter_prefix" {
  description = "Prefix for SSM parameter names (e.g., 'golden-ami/windows-2025'). Used to scope IAM permissions."
  type        = string
}

variable "target_account_ids" {
  description = "Target AWS account IDs for cross-account AMI distribution. Used to grant Image Builder execution role permission to assume distribution roles in target accounts."
  type        = list(string)
  default     = []
}
