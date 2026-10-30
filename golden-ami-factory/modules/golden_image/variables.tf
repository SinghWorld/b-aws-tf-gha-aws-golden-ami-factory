variable "name_prefix" {
  type = string
}

variable "os_key" {
  description = "Catalog key, for example windows-2025 or rhel-9."
  type        = string
}

variable "os_family" {
  description = "OS family. Image Builder only accepts systems_manager_agent configuration for Linux recipes."
  type        = string

  validation {
    condition     = contains(["linux", "windows"], var.os_family)
    error_message = "os_family must be linux or windows."
  }
}

variable "display_name" {
  description = "Human name used in the AMI name, for example 'Windows 2025'."
  type        = string
}

variable "ami_os_code" {
  description = "Short OS identifier used in the AMI name, e.g. rhel8 or win2025."
  type        = string
}

variable "ami_name_prefix" {
  description = "Prefix used for the published AMI name."
  type        = string
}

variable "ami_architecture" {
  description = "Architecture token used in the published AMI name."
  type        = string
}

variable "ami_date_token" {
  description = "Dynamic YYMM token used in the published AMI name."
  type        = string
}

variable "ami_release_version" {
  description = "Release suffix used after the YYMM token."
  type        = string
}

variable "parent_image_arn" {
  type = string
}

variable "component_arns" {
  description = "Ordered list of build and test component ARNs."
  type        = list(string)
}

variable "stig_component_arn" {
  description = "Amazon-managed STIG component ARN that receives the configured Level parameter."
  type        = string
}

variable "stig_level" {
  description = "STIG severity passed to the Amazon-managed component's Level parameter."
  type        = string

  validation {
    condition     = contains(["low", "medium", "high"], var.stig_level)
    error_message = "stig_level must be low, medium or high."
  }
}

variable "root_device_name" {
  type    = string
  default = "/dev/sda1"
}

variable "root_volume_size" {
  type = number
}

variable "kms_key_arn" {
  description = "EBS KMS key ARN used for build volumes and the output AMI snapshots."
  type        = string
}

variable "instance_types" {
  type = list(string)
}

variable "subnet_id" {
  type = string
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name used by Image Builder build and test instances."
  type        = string
}

variable "security_group_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "sns_topic_arn" {
  type    = string
  default = null
}

variable "log_bucket_name" {
  description = "Name of the existing S3 bucket where Image Builder writes logs."
  type        = string
}

variable "log_bucket_prefix" {
  description = "Base S3 key prefix for Image Builder logs."
  type        = string
}

variable "ssm_parameter_name" {
  description = "SSM parameter that always holds the newest AMI ID for this image."
  type        = string
}

variable "target_account_ids" {
  description = "Accounts that receive a copy of the AMI and their own SSM parameter. Empty for single-account."
  type        = list(string)
  default     = []
}

variable "schedule_expression" {
  description = "Image Builder cron expression, or null to trigger builds externally."
  type        = string
  default     = null
}

variable "schedule_timezone" {
  type    = string
  default = "Australia/Sydney"
}

variable "test_timeout_minutes" {
  type    = number
  default = 120
}

variable "images_to_retain" {
  description = "Newest images kept by the lifecycle policy. 0 disables the policy."
  type        = number
  default     = 3
}

variable "lifecycle_role_arn" {
  description = "Execution role ARN for the Image Builder lifecycle policy."
  type        = string
}

variable "imagebuilder_execution_role_arn" {
  description = "Execution role ARN for the Image Builder distribution configuration (used for SSM parameter writes)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
