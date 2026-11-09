# Cross-Account AMI Sharing - Enterprise Guide

## Overview

This project uses **AWS EC2 Image Builder's native cross-account distribution** to automatically share AMIs with target accounts during pipeline execution. No separate Terraform configuration or apply is required beyond the initial setup.

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

## Adding More Accounts

To add more AWS accounts for AMI distribution:

### Option 1: Update the Default (Recommended for Permanent Additions)

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

### Option 2: Override via Command Line (For One-Time or Testing)

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

```bash
# List shared AMIs in target account
aws ec2 describe-images --owners 732533289325 --filters "Name=name,Values=jq-golden-ami-*" --region us-east-1
```

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
- `sts:AssumeRole` on the distribution role in each target account

The `foundation` module **dynamically generates** the cross-account assume role permissions based on `var.target_account_ids`. No code changes needed when adding/removing accounts.

## Target Account Prerequisites

Each target account **must** have the following IAM role for Image Builder to assume during distribution:

```hcl
# In TARGET ACCOUNT (e.g., 774133226694, 373160674113):
resource "aws_iam_role" "imagebuilder_distribution_cross_account" {
  name = "EC2ImageBuilderDistributionCrossAccountRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::SOURCE_ACCOUNT_ID:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "imagebuilder-distribution"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "distribution" {
  role       = aws_iam_role.imagebuilder_distribution_cross_account.name
  policy_arn = "arn:aws:iam::aws:policy/EC2ImageBuilderDistributionCrossAccountRolePolicy"
}
```

**Required AWS Managed Policy:** `EC2ImageBuilderDistributionCrossAccountRolePolicy` (or equivalent custom policy with `ec2:ModifyImageAttribute`, `ec2:CopyImage`, `ssm:PutParameter` on target account resources).

### Automated Target Account Setup (Optional)

For enterprise deployments, consider using **AWS Organizations** + **StackSets** to automatically deploy the cross-account role to all accounts tagged with `GoldenAMI = true`.

## Encryption Considerations

### Default (Unencrypted)
- Works out of the box for cross-account sharing
- No KMS configuration required
- AMIs are unencrypted in all accounts

### Encrypted AMIs (Customer Managed Keys)
When `var.ebs_encrypted = true`:

1. **Source Account**: Requires customer managed KMS key (`var.ebs_kms_key_alias`)
2. **Key Policy**: Must allow `imagebuilder.amazonaws.com` and target accounts
3. **Target Accounts**: Image Builder re-encrypts with each target's KMS key
4. **Target KMS**: Each target needs a KMS key accessible by Image Builder

```hcl
# Source account key policy must include:
{
  "Sid": "AllowImageBuilder",
  "Effect": "Allow",
  "Principal": { "Service": "imagebuilder.amazonaws.com" },
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:DescribeKey"
  ],
  "Resource": "*"
}

# Plus cross-account access for each target:
{
  "Sid": "AllowTargetAccounts",
  "Effect": "Allow",
  "Principal": { "AWS": ["arn:aws:iam::TARGET_ACCOUNT_1:root", ...] },
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*"
  ],
  "Resource": "*"
}
```

## Limits & Quotas

| Limit | Default | Notes |
|-------|---------|-------|
| AMI sharing per AMI | 50 accounts | Request increase via AWS Support |
| AMI copy per region | 50 concurrent | Per account limit |
| KMS key policy size | 32 KB | May need multiple statements for many accounts |

## Troubleshooting

### AMI Not Shared
```bash
# Check launch permissions in target account
aws ec2 describe-image-attribute --image-id ami-xxxxx --attribute launchPermission --region us-east-1
```

### SSM Parameter Missing in Target
```bash
# Verify execution role has ssm:PutParameter in target
aws iam simulate-principal-policy --policy-source-arn <execution-role-arn> --action-names ssm:PutParameter --resource-arns "arn:aws:ssm:us-east-1:TARGET_ACCOUNT:parameter/golden-ami/*"
```

### KMS Access Denied
- Verify source KMS key policy allows target accounts
- Verify target KMS key allows `imagebuilder.amazonaws.com`
- Check CloudTrail for `KMS.Decrypt` events

## Future Enhancement: accounts.yaml (Planned)

For dynamic, GitOps-friendly account management, see `SOLUTION.md` for the planned `accounts.yaml` approach that will replace static `target_account_ids` with a declarative account registry.

---

*Document Version: 2.0*  
*Author: Platform Engineering*  
*Last Updated: 2025-11-06*