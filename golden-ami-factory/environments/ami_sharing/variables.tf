variable "deployments" {
  description = "AWS accounts and regions that can be selected as Terraform deployment targets."
  type = map(object({
    account_name = string
    account_id   = string
    aws_region   = string
  }))
  default = {
    jetstarairwaysnonprod_syd = {
      account_name = "Balraj Singh"
      account_id   = "373160674113"
      aws_region   = "us-east-1"
    }
  }

  validation {
    condition     = alltrue([for deployment in values(var.deployments) : can(regex("^[0-9]{12}$", deployment.account_id)) && length(trimspace(deployment.aws_region)) > 0])
    error_message = "Each deployment must have a 12-digit AWS account_id and a non-empty aws_region."
  }
}

variable "deployment_name" {
  description = "Key in deployments identifying the AWS account where Terraform will create resources."
  type        = string
  default     = "jetstarairwaysnonprod_syd"

  validation {
    condition     = contains(keys(var.deployments), var.deployment_name)
    error_message = "deployment_name must match a key defined in deployments."
  }
}

variable "project" {
  type    = string
  default = "jq-golden-ami"
}

variable "enabled_os" {
  description = "Which images to share."
  type        = list(string)
  default     = ["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"]

  validation {
    condition     = length(var.enabled_os) == length(distinct(var.enabled_os)) && alltrue([for o in var.enabled_os : contains(["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"], o)])
    error_message = "enabled_os must contain unique supported keys: rhel-8, rhel-9, rhel-10, windows-2022, windows-2025."
  }
}

variable "ssm_parameter_prefix" {
  description = "SSM Parameter Store prefix for the latest-AMI parameters."
  type        = string
  default     = "/golden-ami"
}

variable "target_account_ids" {
  description = "AWS account IDs to share the AMIs with. Required for cross-account sharing."
  type        = list(string)
  default     = []
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}