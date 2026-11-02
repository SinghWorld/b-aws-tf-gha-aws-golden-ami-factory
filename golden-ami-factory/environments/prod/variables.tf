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
  description = "Which images to build."
  type        = list(string)
  default     = ["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"]

  validation {
    condition     = length(var.enabled_os) == length(distinct(var.enabled_os)) && alltrue([for o in var.enabled_os : contains(["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"], o)])
    error_message = "enabled_os must contain unique supported keys: rhel-8, rhel-9, rhel-10, windows-2022, windows-2025."
  }
}

variable "vpc_id" {
  description = "VPC for build instances. Needs outbound internet or VPC endpoints for SSM, S3 and package repos."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for build instances."
  type        = string
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name in the deployment account and region for Image Builder instances."
  type        = string
  default     = "MYLABKEY"
}

variable "log_bucket_name" {
  description = "Name of the existing S3 bucket used for Image Builder logs."
  type        = string
  default     = "jcp-infra-nonprod"
}

variable "log_bucket_prefix" {
  description = "S3 key prefix for all Image Builder logs."
  type        = string
  default     = "golden-ami-factory"
}

variable "ebs_encrypted" {
  description = "Whether to encrypt EBS volumes and output AMI snapshots. Set to false for no encryption."
  type        = bool
  default     = false
}

variable "ebs_kms_key_alias" {
  description = "Alias of the EBS KMS key. alias/aws/ebs works for a single account; use a customer managed key before distributing to other accounts. Only used when ebs_encrypted = true."
  type        = string
  default     = "alias/aws/ebs"
}

variable "stig_level" {
  description = "Amazon-managed STIG component level passed to its Level parameter."
  type        = string
  default     = "medium"

  validation {
    condition     = contains(["low", "medium", "high"], var.stig_level)
    error_message = "stig_level must be low, medium or high."
  }
}

variable "ami_date_token" {
  description = "Optional YYMM AMI date token override. Null derives YYMM from the Terraform plan timestamp."
  type        = string
  default     = null

  validation {
    condition     = var.ami_date_token == null ? true : try(can(regex("^[0-9]{4}$", var.ami_date_token)) && tonumber(substr(var.ami_date_token, 2, 2)) >= 1 && tonumber(substr(var.ami_date_token, 2, 2)) <= 12, false)
    error_message = "ami_date_token must be a valid four-digit YYMM value, or null."
  }
}

variable "ami_date_format" {
  description = "Terraform formatdate() pattern for the dynamic AMI date token."
  type        = string
  default     = "YYMM"
}

variable "ami_name_prefix" {
  description = "Prefix for published AMI names."
  type        = string
  default     = "jq-golden-ami"
}

variable "ami_architecture" {
  description = "Architecture token included in published AMI names."
  type        = string
  default     = "x86_64"
}

variable "ami_release_version" {
  description = "Release number appended after the monthly date token, e.g. 1 produces YYMM.1."
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^[0-9]+$", var.ami_release_version))
    error_message = "ami_release_version must contain digits only."
  }
}

variable "ssm_parameter_prefix" {
  description = "SSM Parameter Store prefix for the latest-AMI parameters."
  type        = string
  default     = "/golden-ami"
}

variable "target_account_ids" {
  description = "Distribution accounts. Leave empty for the single-account phase."
  type        = list(string)
  default     = []
}

variable "pipeline_schedule_expression" {
  description = "Native Image Builder cron, for example cron(0 3 1 * ? *). Null means the monthly GitHub workflow starts the builds."
  type        = string
  default     = null
}

variable "windows_instance_types" {
  type    = list(string)
  default = ["m6i.large", "m5.large"]
}

variable "linux_instance_types" {
  type    = list(string)
  default = ["m6i.large", "m5.large"]
}

variable "images_to_retain" {
  type    = number
  default = 3
}

variable "notification_emails" {
  type    = list(string)
  default = []
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
