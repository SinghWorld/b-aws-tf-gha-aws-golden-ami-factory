# Configurable Values from terraform.tfvars

This document summarizes all the values that can now be configured from `terraform.tfvars` in the AWS Golden AMI Factory project.

## Overview

The entire configuration has been refactored so that **terraform.tfvars is the single source of truth** for all environment-specific values. All hardcoded values in modules and locals have been replaced with variables that can be overridden in `terraform.tfvars`.

---

## Files Modified

### 1. `environments/prod/terraform.tfvars` - **Main Configuration File**
Complete rewrite with all configurable values organized into logical sections:
- Deployment Targets
- Network Configuration
- Project Metadata & Tags
- EC2 Infrastructure
- EBS Encryption
- AMI Naming Convention
- Compliance & Hardening
- Recipe Selection
- Default Recipe Settings
- Cross-Account AMI Sharing
- Instance Types
- Pipeline Scheduling
- Test & Lifecycle Settings
- Advanced Settings

### 2. `environments/prod/variables.tf`
Added comprehensive variable definitions with:
- Type constraints
- Default values
- Validation rules
- Descriptions

### 3. `environments/prod/locals.tf`
Updated to use variables from `terraform.tfvars` instead of hardcoded values

### 4. `environments/prod/main.tf`
Updated to pass all new variables to modules

### 5. `modules/recipe_registry/variables.tf`
Added new variables:
- `default_root_volume_size`
- `default_lifecycle_policy_count`

### 6. `modules/recipe_registry/main.tf`
Updated to use new default variables and pass them to recipe interpolation

### 7. `modules/recipe_registry/recipes/*.yaml` (5 files)
Updated all recipe YAML files to use template variables:
- `${default_stig_level}`
- `${default_root_volume_size}`
- `${default_lifecycle_policy_count}`

---

## All Configurable Values

### Deployment Targets
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `deployments` | map(object) | See tfvars | AWS accounts/regions for deployment |
| `deployment_name` | string | `"jetstarairwaysnonprod_syd"` | Selected deployment target |

### Network
| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `vpc_id` | string | Yes | VPC for build instances |
| `subnet_id` | string | Yes | Private subnet for build instances |

### Project Metadata & Tags
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project` | string | `"jq-golden-ami"` | Project name prefix |
| `common_tags` | map(string) | See tfvars | Common tags for all resources |
| `extra_tags` | map(string) | `{}` | Additional tags merged with common_tags |

### EC2 Infrastructure
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `key_pair_name` | string | `"MYLABKEY"` | EC2 key pair name |
| `log_bucket_name` | string | `""` | S3 bucket for logs (optional) |

### EBS Encryption
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ebs_encrypted` | bool | `false` | Enable EBS/AMI encryption |
| `ebs_kms_key_alias` | string | `"alias/aws/ebs"` | KMS key alias for encryption |

### AMI Naming
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ami_name_prefix` | string | `"jq-golden-ami"` | AMI name prefix |
| `ami_architecture` | string | `"x86_64"` | Architecture token |
| `ami_date_format` | string | `"YYMM"` | Date format pattern |
| `ami_date_token` | string | `null` | Optional date override |
| `ami_release_version` | string | `"1"` | Release version suffix |
| `ssm_parameter_prefix` | string | `"/golden-ami"` | SSM parameter prefix |

### Compliance
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `stig_level` | string | `"high"` | STIG level (low/medium/high) |

### Recipe Selection
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enabled_recipes` | list(string) | All 5 recipes | Recipes to enable |
| `enabled_os` | list(string) | `[]` | Legacy OS selection |

### Default Recipe Settings
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `default_root_volume_size` | number | `100` | Default root volume (GB) |
| `default_lifecycle_policy_count` | number | `3` | Default AMIs to retain |
| `default_stig_level` | string | `"high"` | Default STIG level |

### Cross-Account Sharing
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `target_account_ids` | list(string) | `["774133226694", "373160674113"]` | Target accounts for AMI sharing |

### Instance Types
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `windows_instance_types` | list(string) | `["t3.large", "t3a.large"]` | Windows instance types |
| `linux_instance_types` | list(string) | `["t3.large", "t3a.large"]` | Linux instance types |

### Pipeline Scheduling
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `pipeline_schedule_expression` | string | `"cron(0 3 1 * ? *)"` | Image Builder cron |
| `schedule_timezone` | string | `"Australia/Sydney"` | Schedule timezone |

### Test & Lifecycle
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `test_timeout_minutes` | number | `120` | Test timeout |
| `images_to_retain` | number | `2` | AMIs to retain (per pipeline) |

### Advanced Settings
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `linux_root_device_name` | string | `"/dev/xvda"` | Linux root device |
| `windows_root_device_name` | string | `"/dev/sda1"` | Windows root device |
| `install_cloudwatch_agent` | bool | `true` | Enable CloudWatch Agent |
| `enable_boot_test` | bool | `true` | Enable boot test |
| `enable_stig` | bool | `true` | Enable STIG hardening |
| `component_version` | string | `"1.0.0"` | Component version |

---

## Usage

### To change any value:
1. Edit `environments/prod/terraform.tfvars`
2. Run `terraform plan` to see changes
3. Run `terraform apply` to apply changes

### Example: Change retention to 5 AMIs
```hcl
# In terraform.tfvars
images_to_retain = 5
```

### Example: Enable encryption with customer managed key
```hcl
# In terraform.tfvars
ebs_encrypted = true
ebs_kms_key_alias = "alias/ebs-golden"
```

### Example: Build only RHEL 9 and Windows 2025
```hcl
# In terraform.tfvars
enabled_recipes = ["rhel-9", "windows-2025"]
```

### Example: Change schedule to weekly
```hcl
# In terraform.tfvars
pipeline_schedule_expression = "cron(0 3 ? * MON *)"
```

### Example: Add custom tags
```hcl
# In terraform.tfvars
extra_tags = {
  Project     = "Golden-AMI"
  Team        = "Platform"
  CostCenter  = "12345"
}
```

---

## Architecture Notes

### Variable Flow
```
terraform.tfvars
      ↓
variables.tf (validation & defaults)
      ↓
locals.tf (computed values)
      ↓
main.tf (passed to modules)
      ↓
modules/foundation, components, recipe_registry, golden_image
```

### Recipe Registry Flow
```
terraform.tfvars → variables.tf → recipe_registry module
                                      ↓
                          Reads recipes/*.yaml with template vars
                                      ↓
                          Outputs normalized recipes
                                      ↓
                          golden_image module consumes them
```

### Key Benefits
1. **Single Source of Truth** - All config in one file
2. **No Code Changes** - Modify tfvars only for new environments
3. **Validation** - All variables have type checking and validation
4. **Documentation** - Each variable has clear description
5. **GitOps Friendly** - Recipe YAML files use template variables
6. **Backward Compatible** - Legacy variables still supported

---

## Migration Notes

If upgrading from a previous version:

1. **Review `terraform.tfvars`** - All your previous hardcoded values should now be in this file
2. **Run `terraform plan`** - Expect some recipe replacements due to:
   - Root device name changes (Linux: `/dev/sda1` → `/dev/xvda`)
   - Volume size changes (Windows 2025: 50GB → 100GB default)
   - These are normal and expected
3. **Apply changes** - The replacements use `create_before_destroy` so pipelines remain available

---

## Last Updated
- Date: 2025-11-09
- Project: AWS Golden AMI Factory
- Version: 2.0 (Full tfvars configuration)