# AWS Golden AMI Factory

A Terraform-based solution for building hardened, compliant Golden AMIs using EC2 Image Builder, with optional cross-account sharing capabilities.

## Features

- **Multi-OS Support**: RHEL 8, 9, 10 and Windows Server 2022, 2025
- **Security Hardening**: STIG compliance (Low/Medium/High), custom hardening components
- **CloudWatch Agent**: Pre-installed and configured for metrics and logs collection
- **SSM Agent**: Automatic installation and management
- **Optional EBS Encryption**: Configurable encryption with customer-managed KMS keys
- **Cross-Account AMI Sharing**: Share built AMIs with multiple AWS accounts
- **Lifecycle Management**: Automatic retention of N newest images
- **GitHub Actions Integration**: CI/CD pipeline for automated monthly builds

## Architecture

```
+---------------------------------------------------------------------------+
|                      SOURCE ACCOUNT (Build Account)                        |
|  +-----------------+    +------------------+    +----------------------+  |
|  |  EC2 Image      |--->|  Distribution    |--->|  SSM Parameter Store |  |
|  |  Builder        |    |  Configuration   |    |  (Latest AMI IDs)    |  |
|  +-----------------+    +------------------+    +----------+-----------+  |
|        |                       |                       |              |
|        v                       v                       v              |
|  +---------------------------------------------------------------------------+  |
|  |                  AMI Sharing Module (Optional)                             |  |
|  |      Reads AMI IDs from SSM -> Shares with Target Accounts                |  |
|  +---------------------------------------------------------------------------+  |
+-------------------------------------------------------------------------------+
                                    |
                                    v
+---------------------------------------------------------------------------+
|                      TARGET ACCOUNTS (Multiple)                           |
|  +--------------+  +--------------+  +--------------+                     |
|  |  Account A   |  |  Account B   |  |  Account C   |  ...                |
|  |  (AMI Copy)  |  |  (AMI Copy)  |  |  (AMI Copy)  |                     |
|  +--------------+  +--------------+  +--------------+                     |
+---------------------------------------------------------------------------+
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

## Cross-Account AMI Sharing

### Overview

The AMI sharing feature allows you to share built Golden AMIs with multiple target AWS accounts. This is deployed **in the source/build account** after AMIs are built and their IDs stored in SSM Parameter Store.

### Step-by-Step: Configure Multiple Target Accounts

#### Step 1: Prepare Target Account IDs

Collect the 12-digit AWS Account IDs you want to share AMIs with:

```text
Account A: 111111111111  (e.g., Development)
Account B: 222222222222  (e.g., Staging)
Account C: 333333333333  (e.g., Production)
```

#### Step 2: Configure ami_sharing Environment

```bash
cd ../ami_sharing
```

Create `backend.hcl` (can use same state bucket, different key):

```hcl
bucket         = "your-terraform-state-bucket"
key            = "golden-ami-factory/ami-sharing/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-locks"
encrypt        = true
```

Create `terraform.tfvars`:

```hcl
# Deployment target (same as prod - the SOURCE account)
deployment_name = "jetstarairwaysnonprod_syd"

# OS keys to share (must match what was built in prod)
enabled_os = ["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"]

# SSM parameter prefix (must match prod)
ssm_parameter_prefix = "/golden-ami"

# TARGET ACCOUNTS - List of 12-digit AWS Account IDs
target_account_ids = [
  "111111111111",  # Development
  "222222222222",  # Staging
  "333333333333",  # Production
]
```

#### Step 3: Deploy AMI Sharing

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

This will:
1. Read AMI IDs from SSM parameters (`/golden-ami/{os-key}/latest`)
2. Create `aws_ec2_ami_launch_permission` resources for each AMI
3. Grant launch permissions to all target accounts

#### Step 4: Verify in Target Accounts

In each target account, verify the shared AMI is visible:

```bash
# List shared AMIs (run in TARGET account)
aws ec2 describe-images \
  --owners 123456789012 \  # Source account ID
  --filters "Name=name,Values=jq-golden-ami-*"
```

Or via Console: EC2 -> AMIs -> "Private images" -> "Shared with me"

#### Step 5: (Optional) Create SSM Parameters in Target Accounts

Target accounts can create their own SSM parameters pointing to the shared AMIs:

```bash
# In TARGET account, for each OS:
aws ssm put-parameter \
  --name "/golden-ami/rhel-9/latest" \
  --type "String" \
  --value "ami-0abcdef1234567890" \
  --data-type "aws:ec2:image" \
  --overwrite
```

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

### Environment Variables (ami_sharing)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `deployment_name` | string | `jetstarairwaysnonprod_syd` | Source account deployment |
| `enabled_os` | list(string) | All 5 OSes | Which AMIs to share |
| `ssm_parameter_prefix` | string | `/golden-ami` | SSM prefix for AMI IDs |
| `target_account_ids` | list(string) | **Required** | Target AWS account IDs |

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
# Destroy AMI sharing first
cd environments/ami_sharing
terraform destroy

# Then destroy prod
cd ../prod
terraform destroy
```

---

## License

Internal use only - Jetstar Airways / Tech Infra Cloud