# =============================================================================
# Variables for AWS Golden AMI Factory - Production Environment
# All defaults can be overridden in terraform.tfvars
# =============================================================================

# -----------------------------------------------------------------------------
# DEPLOYMENT TARGETS
# -----------------------------------------------------------------------------

variable "deployments" {
  description = "AWS accounts and regions that can be selected as Terraform deployment targets. The account_id should be the TARGET account where resources are created (e.g., Development account)."
  type = map(object({
    account_name = string
    account_id   = string
    aws_region   = string
  }))
  default = {
    jetstarairwaysnonprod_syd = {
      account_name = "Development"
      account_id   = "732533289325" # Development account - where AMIs are built
      aws_region   = "ap-southeast-2"
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

# -----------------------------------------------------------------------------
# PROJECT METADATA & TAGS
# -----------------------------------------------------------------------------

variable "project" {
  type    = string
  default = "jq-golden-ami"
}

variable "common_tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {
    CostCentre  = "579087"
    CreatedBy   = "DL-TechInfraCloud@singhworld.com"
    Environment = "Production"
    DeployedBy  = "IAC using Terraform"
    Owner       = "DL-TechInfraCloud@singhworld.com"
    ProtectedBy = "Tech-Infra-Cloud@singhworld.com"
  }
}

variable "extra_tags" {
  description = "Additional tags merged with common_tags."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# NETWORK CONFIGURATION
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC for build instances. Needs outbound internet or VPC endpoints for SSM, S3 and package repos."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for build instances."
  type        = string
}

# -----------------------------------------------------------------------------
# EC2 INFRASTRUCTURE
# -----------------------------------------------------------------------------

variable "key_pair_name" {
  description = "Existing EC2 key pair name in the deployment account and region for Image Builder instances."
  type        = string
  default     = "MYLABKEY"
}

variable "log_bucket_name" {
  description = "S3 bucket for Image Builder logs. Optional - leave empty for default."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# EBS ENCRYPTION
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# AMI NAMING CONVENTION
# -----------------------------------------------------------------------------

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

variable "ami_date_format" {
  description = "Terraform formatdate() pattern for the dynamic AMI date token."
  type        = string
  default     = "YYMM"
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

variable "ami_release_version" {
  description = "Release number appended after the monthly date token (e.g. 1 produces YYMM.1). Set to empty string to omit version and use build timestamp only for uniqueness."
  type        = string
  default     = ""

  validation {
    condition     = var.ami_release_version == "" ? true : can(regex("^[0-9]+$", var.ami_release_version))
    error_message = "ami_release_version must contain digits only, or be empty string."
  }
}

variable "ssm_parameter_prefix" {
  description = "SSM Parameter Store prefix for the latest-AMI parameters."
  type        = string
  default     = "/golden-ami"
}

# -----------------------------------------------------------------------------
# COMPLIANCE & HARDENING
# -----------------------------------------------------------------------------

variable "stig_level" {
  description = "Amazon-managed STIG component level passed to its Level parameter (low, medium, high)."
  type        = string
  default     = "high"

  validation {
    condition     = contains(["low", "medium", "high"], var.stig_level)
    error_message = "stig_level must be low, medium, or high."
  }
}

# -----------------------------------------------------------------------------
# RECIPE SELECTION (New Recipe Registry)
# -----------------------------------------------------------------------------

variable "enabled_os" {
  description = "Which images to build (legacy - use enabled_recipes for new recipe registry)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.enabled_os) == 0 || (length(var.enabled_os) == length(distinct(var.enabled_os)) && alltrue([for o in var.enabled_os : contains(["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"], o)]))
    error_message = "enabled_os must contain unique supported keys: rhel-8, rhel-9, rhel-10, windows-2022, windows-2025."
  }
}

variable "enabled_recipes" {
  description = "Recipe keys to enable from the recipe registry. Empty means all recipes in index.yaml. Example: ['rhel-9', 'windows-2025']"
  type        = list(string)
  default     = ["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"]
}

# -----------------------------------------------------------------------------
# DEFAULT RECIPE SETTINGS
# -----------------------------------------------------------------------------

variable "default_root_volume_size" {
  description = "Default root volume size in GB."
  type        = number
  default     = 100
}

variable "default_lifecycle_policy_count" {
  description = "Default number of AMIs to retain per OS (0 disables)."
  type        = number
  default     = 3
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

# -----------------------------------------------------------------------------
# CROSS-ACCOUNT AMI SHARING
# -----------------------------------------------------------------------------

variable "target_account_ids" {
  description = "Distribution accounts to share AMIs with. Image Builder will automatically share AMIs and create SSM parameters in these accounts."
  type        = list(string)
  default     = ["774133226694", "373160674113"]
}

# -----------------------------------------------------------------------------
# INSTANCE TYPES
# -----------------------------------------------------------------------------

variable "windows_instance_types" {
  description = "Instance types for Windows builds (fallback order)."
  type        = list(string)
  default     = ["t3.large", "t3a.large"]
}

variable "linux_instance_types" {
  description = "Instance types for Linux builds (fallback order)."
  type        = list(string)
  default     = ["t3.large", "t3a.large"]
}

# -----------------------------------------------------------------------------
# PIPELINE SCHEDULING
# -----------------------------------------------------------------------------

variable "pipeline_schedule_expression" {
  description = "Native Image Builder cron expression, for example cron(0 3 1 * ? *). Null means the monthly GitHub workflow starts the builds."
  type        = string
  default     = "cron(0 3 1 * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone for the schedule expression."
  type        = string
  default     = "Australia/Sydney"
}

# -----------------------------------------------------------------------------
# TEST & LIFECYCLE SETTINGS
# -----------------------------------------------------------------------------

variable "test_timeout_minutes" {
  description = "Test timeout in minutes for Image Builder image tests."
  type        = number
  default     = 120
}

variable "images_to_retain" {
  description = "Newest images kept by the lifecycle policy. 0 disables the policy."
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# ADVANCED SETTINGS
# -----------------------------------------------------------------------------

variable "linux_root_device_name" {
  description = "Root device name for Linux images."
  type        = string
  default     = "/dev/xvda"
}

variable "windows_root_device_name" {
  description = "Root device name for Windows images."
  type        = string
  default     = "/dev/sda1"
}

variable "install_cloudwatch_agent" {
  description = "Enable CloudWatch Agent installation (uses AWS-managed component)."
  type        = bool
  default     = true
}

variable "enable_boot_test" {
  description = "Enable boot verification test (uses AWS-managed component)."
  type        = bool
  default     = true
}

variable "enable_stig" {
  description = "Enable STIG hardening component (AWS-managed)."
  type        = bool
  default     = true
}

variable "component_version" {
  description = "Component version for custom components (managed by content hash)."
  type        = string
  default     = "1.0.0"
}