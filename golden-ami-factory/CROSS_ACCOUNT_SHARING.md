# Cross-Account AMI Sharing - Modular Approach

## Overview

This project uses **AWS Image Builder's native cross-account distribution** to automatically share AMIs with target accounts during pipeline execution. No separate Terraform configuration or apply is required.

## How It Works

The `golden_image` module's `aws_imagebuilder_distribution_configuration` (in `modules/golden_image/main.tf`) handles everything:

```hcl
resource "aws_imagebuilder_distribution_configuration" "this" {
  # ...
  
  distribution {
    region = data.aws_region.current.region
    
    ami_distribution_configuration {
      # ... other settings ...
      target_account_ids = var.target_account_ids  # <-- Shares AMI with these accounts
    }
    
    # SSM parameter in build account
    ssm_parameter_configuration {
      parameter_name = var.ssm_parameter_name
      data_type      = "aws:ec2:image"
    }
    
    # SSM parameter in EACH target account (automatic!)
    dynamic "ssm_parameter_configuration" {
      for_each = toset(var.target_account_ids)
      content {
        ami_account_id = ssm_parameter_configuration.value
        parameter_name = var.ssm_parameter_name
        data_type      = "aws:ec2:image"
      }
    }
  }
}
```

## Current Configuration

Target accounts are configured in **`environments/prod/variables.tf`**:

```hcl
variable "target_account_ids" {
  description = "Distribution accounts to share AMIs with. Image Builder will automatically share AMIs and create SSM parameters in these accounts."
  type        = list(string)
  default     = ["774133226694", "373160674113"]
}
```

## Adding More Accounts (Modular Approach)

To add more AWS accounts for AMI distribution:

### Option 1: Update the Default (Recommended for permanent additions)

Edit `environments/prod/variables.tf` and add the account ID to the default list:

```hcl
default     = ["774133226694", "373160674113", "NEW_ACCOUNT_ID_HERE"]
```

Then run:
```bash
cd environments/prod
terraform apply
```

The next pipeline execution will automatically share AMIs with the new account.

### Option 2: Override via Command Line (For one-time or testing)

```bash
cd environments/prod
terraform apply -var='target_account_ids=["774133226694", "373160674113", "NEW_ACCOUNT_ID"]'
```

### Option 3: Override via Environment Variable (For CI/CD)

```bash
export TF_VAR_target_account_ids='["774133226694", "373160674113", "NEW_ACCOUNT_ID"]'
terraform apply
```

## What Happens Automatically

When the Image Builder pipeline runs:

1. **AMI is built** in the source account (732533289325)
2. **AMI is shared** with all accounts in `target_account_ids`
3. **SSM parameter** `/golden-ami/{os_key}/latest` is created in:
   - The source account
   - Each target account (same parameter name, account-specific value)
4. **Lifecycle policy** manages retention in the source account

## Verification

After a pipeline run, verify in each target account:

```bash
# In target account (e.g., 774133226694)
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1
```

The parameter value will be the AMI ID shared from the source account.

## Architecture Benefits

| Aspect | Benefit |
|--------|---------|
| **Single apply** | One `terraform apply` in prod configures everything |
| **Native AWS** | Uses Image Builder's built-in cross-account distribution |
| **Atomic** | Sharing happens during build - no drift |
| **Automated SSM** | Parameters created in all accounts automatically |
| **Modular** | Add accounts by updating one variable |
| **No extra state** | Single Terraform state file |
| **No extra IAM** | Image Builder execution role handles cross-account permissions |

## Required Permissions

The Image Builder execution role (created by `foundation` module) needs:

- `ec2:ModifyImageAttribute` on the AMI (for sharing)
- `ssm:PutParameter` in target accounts (for SSM parameters)

The `foundation` module creates the appropriate IAM policies with cross-account permissions.

## Deprecated: ami_sharing Environment

The `environments/ami_sharing` directory is **deprecated**. It previously used a separate Terraform module to read AMI IDs from SSM and share them post-build. This is no longer needed because Image Builder does it natively during the build.

See `environments/ami_sharing/README.md` for details.