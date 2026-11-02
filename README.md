# AWS Golden AMI Factory

A Terraform-based solution for building hardened, compliant Golden AMIs using EC2 Image Builder, with optional cross-account sharing capabilities.

## Features

- **Multi-OS Support**: RHEL 8, 9, 10 and Windows Server 2022, 2025
- **Security Hardening**: STIG compliance (Low/Medium/High), custom hardening components
- **CloudWatch Agent**: Pre-installed and configured for metrics and logs collection
- **SSM Agent**: Automatic installation and management
- **Optional EBS Encryption**: Configurable encryption with customer-managed KMS keys
- **Cross-Account AMI Sharing**: Share built AMIs with multiple AWS accounts (native Image Builder distribution)
- **Lifecycle Management**: Automatic retention of N newest images
- **GitHub Actions Integration**: CI/CD pipeline for automated monthly builds

## Architecture

```
+---------------------------------------------------------------------------+
|                      SOURCE ACCOUNT (Build Account)                        |
|  +-----------------+    +------------------------------------------+     |
|  |  EC2 Image      |--->|  Distribution Configuration (Native)     |     |
|  |  Builder        |    |  - Shares AMI with target accounts       |     |
|  +-----------------+    |  - Creates SSM params in ALL accounts    |     |
|                         +----------------------+-------------------+     |
|                                        |                              |
|                                        v                              |
|                         +-----------------------------+              |
|                         |  SSM Parameter Store        |              |
|                         |  (Latest AMI IDs)           |              |
|                         +-----------------------------+              |
+-------------------------------------------------------------------------------+
                                    |
                                    |  (Automatic during build)
                                    v
+---------------------------------------------------------------------------+
|                      TARGET ACCOUNTS (Multiple)                           |
|  +--------------+  +--------------+  +--------------+                     |
|  |  Account A   |  |  Account B   |  |  Account C   |  ...                |
|  |  (AMI Copy)  |  |  (AMI Copy)  |  |  (AMI Copy)  |                     |
|  |  (SSM Param) |  |  (SSM Param) |  |  (SSM Param) |                     |
|  +--------------+  +--------------+  +--------------+                     |
+---------------------------------------------------------------------------+
```

**Key**: AMI sharing and SSM parameter creation happen **natively during Image Builder pipeline execution** - no separate Terraform apply needed.
```

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- Existing VPC with private subnet (with NAT Gateway or VPC endpoints for S3/SSM)
- S3 bucket for Image Builder logs
- EC2 Key Pair in the build region
- IAM permissions for: EC2, Image Builder, IAM, KMS, S3, SNS, SSM

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod
```

### 2. Create Backend Configuration

Create `backend.hcl`:

```hcl
bucket         = "your-terraform-state-bucket"
key            = "golden-ami-factory/prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-locks"
encrypt        = true
```

Initialize:
```bash
terraform init -backend-config=backend.hcl
```

### 3. Configure Variables

Create `terraform.tfvars`:

```hcl
# Deployment target
deployment_name = "jetstarairwaysnonprod_syd"

# VPC and Network (REQUIRED - must exist)
vpc_id     = "vpc-0123456789abcdef0"
subnet_id  = "subnet-0123456789abcdef0"

# Key Pair (REQUIRED - must exist in region)
key_pair_name = "MYLABKEY"

# S3 Log Bucket (REQUIRED - must exist)
log_bucket_name = "your-log-bucket"

# Optional: Enable EBS encryption (default: false)
ebs_encrypted = false

# Optional: Use customer-managed KMS key (required if ebs_encrypted = true)
# ebs_kms_key_alias = "alias/your-custom-key"

# Optional: Target accounts for cross-account sharing (leave empty for single-account)
target_account_ids = []

# Optional: Scheduled builds (null = manual/GitHub Actions triggered)
pipeline_schedule_expression = null

# OS Selection
enabled_os = ["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"]

# STIG Level
stig_level = "medium"

# Instance Types
linux_instance_types  = ["m6i.large", "m5.large"]
windows_instance_types = ["m6i.large", "m5.large"]
```

### 4. Deploy Foundation Resources

```bash
terraform plan -target=module.foundation
terraform apply -target=module.foundation
```

This creates:
- IAM roles (build instance, lifecycle, Image Builder execution)
- Security group (no ingress, HTTPS/HTTP egress)
- SNS topic for build notifications

### 5. Deploy Custom Components

```bash
terraform plan -target=module.components
terraform apply -target=module.components
```

Creates custom Image Builder components:
- SSM Agent (Linux/Windows)
- Hardening (Linux/Windows)
- Validation (Linux/Windows)
- CloudWatch Agent (Linux/Windows)

### 6. Deploy Golden Image Pipelines

```bash
terraform plan
terraform apply
```

Creates for each OS:
- Image Recipe (with component chain)
- Infrastructure Configuration
- Distribution Configuration
- Image Pipeline
- Lifecycle Policy (retains 3 newest AMIs)

### 7. Trigger First Build

**Option A: Manual via AWS Console**
1. Go to EC2 Image Builder -> Image pipelines
2. Select pipeline -> "Run pipeline"

**Option B: Manual via AWS CLI**
```bash
aws imagebuilder start-image-pipeline-execution \
  --image-pipeline-arn <pipeline-arn-from-output>
```

**Option C: GitHub Actions (Recommended)**
See [GitHub Actions Setup](#github-actions-setup) below.

---

## Cross-Account AMI Sharing (Native Image Builder)

### Overview

**AMI sharing is now handled natively by AWS Image Builder's distribution configuration** during pipeline execution. No separate Terraform environment or apply is required.

When the Image Builder pipeline runs, it automatically:
1. **Shares the AMI** with all accounts in `target_account_ids`
2. **Creates SSM parameters** in each target account (same parameter name, account-specific AMI ID)

This is configured entirely in the `prod` environment - single `terraform apply` configures everything.

### Configuration

Set target accounts in `environments/prod/variables.tf` or via `terraform.tfvars`:

```hcl
# In terraform.tfvars or environments/prod/variables.tf default
target_account_ids = [
  "774133226694",  # Account A
  "373160674113",  # Account B
]
```

### Adding More Accounts (Modular Approach)

To add more AWS accounts for AMI distribution:

**Option 1: Update the Default (Recommended for permanent additions)**

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

**Option 2: Override via Command Line**

```bash
cd environments/prod
terraform apply -var='target_account_ids=["774133226694", "373160674113", "NEW_ACCOUNT_ID"]'
```

**Option 3: Override via Environment Variable (For CI/CD)**

```bash
export TF_VAR_target_account_ids='["774133226694", "373160674113", "NEW_ACCOUNT_ID"]'
terraform apply
```

### What Happens Automatically

When the Image Builder pipeline runs:

1. **AMI is built** in the source account (732533289325)
2. **AMI is shared** with all accounts in `target_account_ids`
3. **SSM parameter** `/golden-ami/{os_key}/latest` is created in:
   - The source account
   - Each target account (same parameter name, account-specific value)
4. **Lifecycle policy** manages retention in the source account

### Verification

After a pipeline run, verify in each target account:

```bash
# In target account (e.g., 774133226694)
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1
```

The parameter value will be the AMI ID shared from the source account.

Also verify AMI visibility:
```bash
# In target account
aws ec2 describe-images \
  --owners 732533289325 \  # Source account ID
  --filters "Name=name,Values=jq-golden-ami-*"
```

Or via Console: EC2 -> AMIs -> "Private images" -> "Shared with me"

---

## GitHub Actions Setup

### 1. Configure AWS Credentials

In GitHub Repository Settings -> Secrets and variables -> Actions, add:

| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_ARN` | IAM Role ARN with permissions to deploy (assume role) |
| `AWS_REGION` | `us-east-1` |

Or use OIDC with a GitHub Actions IAM role.

### 2. Workflow File

The repository includes `.github/workflows/build-golden-ami.yml` which:
- Runs monthly on the 1st at 03:00 UTC
- Can be manually triggered with `workflow_dispatch`
- Deploys to `prod` environment
- Triggers Image Builder pipelines

### 3. Manual Trigger

Go to Actions -> "Build Golden AMI" -> "Run workflow" -> Select OS -> Run.

---

## Configuration Reference

### Environment Variables (prod)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `deployment_name` | string | `jetstarairwaysnonprod_syd` | Key in `deployments` map |
| `vpc_id` | string | **Required** | VPC for build instances |
| `subnet_id` | string | **Required** | Private subnet for builds |
| `key_pair_name` | string | `MYLABKEY` | EC2 key pair name |
| `log_bucket_name` | string | `jcp-infra-nonprod` | S3 bucket for logs |
| `log_bucket_prefix` | string | `golden-ami-factory` | S3 key prefix |
| `ebs_encrypted` | bool | `false` | Enable EBS/AMI encryption |
| `ebs_kms_key_alias` | string | `alias/aws/ebs` | KMS key alias (if encrypted) |
| `target_account_ids` | list(string) | `[]` | Accounts for AMI sharing |
| `enabled_os` | list(string) | All 5 OSes | Which images to build |
| `stig_level` | string | `medium` | STIG severity (low/medium/high) |
| `ami_name_prefix` | string | `jq-golden-ami` | AMI name prefix |
| `ami_release_version` | string | `1` | Release suffix (e.g., 1 = YYMM.1) |
| `pipeline_schedule_expression` | string | `null` | Cron for scheduled builds |
| `images_to_retain` | number | `3` | AMIs to retain per OS |
| `notification_emails` | list(string) | `[]` | SNS notification emails |

---

## Component Chain Order

### Linux
1. `update-linux` - OS patches
2. `aws-cli-version-2-linux` - AWS CLI v2
3. `linux-ssm-agent` - SSM Agent install/upgrade
4. `stig-build-linux` - STIG hardening (configurable level)
5. `linux-hardening` - Extra hardening (SSH, kernel, filesystems)
6. `linux-validate` - Baseline validation tests
7. `linux-cloudwatch-agent` - CloudWatch Agent install/config
8. `simple-boot-test-linux` - Boot verification

### Windows
1. `update-windows` - OS patches
2. `aws-cli-version-2-windows` - AWS CLI v2
3. `windows-ssm-agent` - SSM Agent check
4. `stig-build-windows` - STIG hardening (configurable level)
5. `windows-hardening` - Extra hardening (SMB, TLS, Guest)
6. `windows-validate` - Baseline validation tests
7. `windows-cloudwatch-agent` - CloudWatch Agent install/config
8. `simple-boot-test-windows` - Boot verification

---

## Outputs

### Prod Environment
- `pipeline_arns` - Map of OS -> Pipeline ARN
- `ssm_parameters` - Map of OS -> SSM Parameter name
- `ami_name_templates` - Map of OS -> AMI name template
- `kms_key_arn` - KMS key ARN (if encryption enabled)

### AMI Sharing Environment
- `shared_ami_ids` - Map of OS -> Shared AMI ID
- `target_accounts` - List of target account IDs

---

## Troubleshooting

### Build Failures
1. Check Image Builder console: EC2 -> Image Builder -> Image pipelines
2. Check CloudWatch Logs: `/aws/imagebuilder/<pipeline-name>`
3. Check S3 logs bucket: `s3://<bucket>/golden-ami-factory/<os-key>/`

### AMI Not Shared
1. Verify AMI IDs exist in SSM: `aws ssm get-parameters-by-path --path /golden-ami/`
2. Check launch permissions: `aws ec2 describe-image-attribute --image-id ami-xxx --attribute launchPermission`
3. Ensure target accounts are valid 12-digit IDs

### KMS Errors
- If `ebs_encrypted = true`, ensure `ebs_kms_key_alias` points to a valid customer-managed key
- The key must allow `imagebuilder.amazonaws.com` service to use it
- Cross-account sharing with encrypted AMIs requires the target account to have access to the KMS key

---

## Security Considerations

- **No Encryption (Default)**: AMIs are unencrypted, easily shareable across accounts
- **With Encryption**: Requires customer-managed KMS key with cross-account permissions
- **Network**: Build instances in private subnet, no inbound access
- **IAM**: Least-privilege roles for Image Builder, build instances, lifecycle
- **STIG**: Configurable compliance level (Low/Medium/High)

---

## Cleanup

```bash
# Destroy prod (includes AMI sharing configuration)
cd environments/prod
terraform destroy
```

---

## License

Internal use only - Jetstar Airways / Tech Infra Cloud