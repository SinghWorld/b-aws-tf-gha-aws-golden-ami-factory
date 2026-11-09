variable "recipes_path" {
  description = "Path to the recipes directory containing YAML recipe definitions."
  type        = string
  default     = "./recipes"
}

variable "custom_components_arns" {
  description = "Map of custom component keys to their ARNs (with x.x.x version for latest)."
  type        = map(string)
  default     = {}
}

variable "aws_managed_prefix" {
  description = "ARN prefix for AWS-managed resources (components and images). Uses deployment region."
  type        = string
  default     = ""
}

variable "default_stig_level" {
  description = "Default STIG level for STIG components (low, medium, high)."
  type        = string
  default     = "high"

  validation {
    condition     = contains(["low", "medium", "high"], var.default_stig_level)
    error_message = "default_stig_level must be low, medium, or high."
  }
}

variable "default_root_volume_size" {
  description = "Default root volume size in GB."
  type        = number
  default     = 100
}

variable "tags" {
  description = "Tags to apply to all recipes."
  type        = map(string)
  default     = {}
}

variable "enabled_recipes" {
  description = "List of recipe keys to enable. Empty means all recipes in the directory."
  type        = list(string)
  default     = []
}