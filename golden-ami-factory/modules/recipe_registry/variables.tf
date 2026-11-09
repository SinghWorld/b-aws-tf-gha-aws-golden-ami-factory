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

variable "aws_managed_components_prefix" {
  description = "ARN prefix for AWS-managed components (e.g., arn:aws:imagebuilder:region:aws). Use us-east-1 for CIS/STIG components."
  type        = string
  default     = ""
}

variable "aws_managed_images_prefix" {
  description = "ARN prefix for AWS-managed parent images (e.g., arn:aws:imagebuilder:region:aws). Should use the deployment region."
  type        = string
  default     = ""
}

variable "default_cis_level" {
  description = "Default CIS level for CIS components (level-1 or level-2)."
  type        = string
  default     = "level-2"

  validation {
    condition     = contains(["level-1", "level-2"], var.default_cis_level)
    error_message = "default_cis_level must be level-1 or level-2."
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