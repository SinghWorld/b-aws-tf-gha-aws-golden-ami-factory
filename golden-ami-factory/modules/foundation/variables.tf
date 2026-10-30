variable "name_prefix" {
  description = "Prefix applied to every resource name."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the Image Builder build instances."
  type        = string
}

variable "log_bucket_name" {
  description = "Name of the existing S3 bucket used for Image Builder logs."
  type        = string
}

variable "log_bucket_prefix" {
  description = "Existing bucket key prefix under which Image Builder logs are written."
  type        = string
}

variable "notification_emails" {
  description = "Email addresses subscribed to build success/failure notifications."
  type        = list(string)
  default     = []
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
