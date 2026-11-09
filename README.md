# AWS Golden AMI Factory

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5.0-7B42BC.svg)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-%3E%3D5.0-FF9900.svg)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Enterprise-grade Terraform solution for building hardened, compliant Golden AMIs using **EC2 Image Builder** with native cross-account distribution capabilities. Supports **RHEL 8/9/10** and **Windows Server 2022/2025** with STIG compliance, CloudWatch Agent, SSM Agent, and automated cross-account AMI sharing.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Deployment Guide](#detailed-deployment-guide)
- [Adding New Target Accounts](#adding-new-target-accounts)
- [Adding New Recipes](#adding-new-recipes)
- [Configuration Reference](#configuration-reference)
- [Verification & Testing](#verification--testing)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Cleanup](#cleanup)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    MANAGEMENT ACCOUNT (373160674113)            │
│  ┌─────────────┐                                               │
│  │ IAM User    │  AssumeRole → TerraformDeploymentRole        │
│  │ "Terraform" │                                               │
│  └─────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   DEVELOPMENT ACCOUNT (732533289325)            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              TerraformDeploymentRole                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│          ┌───────────────────┼───────────────────┐             │
│          ▼                   ▼                   ▼             │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐      │
│  │  Foundation  │   │  Components  │   │ Golden Image │      │
│  │   Module     │   │   Module     │   │   Module     │      │
│  │  (IAM, SG,   │   │  (Custom     │   │  (Pipelines  │      │
│  │   SNS)       │   │   Components)│   │   per OS)    │      │
│  └──────────────┘   └──────────────┘   └──────┬───────┘      │
│                                                │              │
│                                                ▼              │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │              Image Builder Pipelines                    │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │  │
│  │  │ RHEL 8  │ │ RHEL 9  │ │ RHEL 10 │ │Win 2022 │       │  │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘       │  │
│  └───────┼───────────┼───────────┼───────────┼────────────┘  │
└──────────┼───────────┼───────────┼───────────┼────────────────┘
           │           │           │           │
           ▼           ▼           ▼           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      TARGET ACCOUNTS                            │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ 774133226694     │  │ 373160674113     │  ... (+10 more)   │
│  │ (Production)     │  │ (Management)     │                    │
│  │                  │  │                  │                    │
│  │ • Shared AMIs    │  │ • Shared AMIs    │                    │
│  │ • SSM Params     │  │ • SSM Params     │                    │
│  │ • KMS Key        │  │ • KMS Key        │                    │
│  └──────────────────┘  └──────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Module | Purpose | Resources Created |
|--------|---------|-------------------|
| **Foundation** | IAM roles, security groups, SNS | Build role, instance profile, SG, lifecycle role, Image Builder execution role |
| **Components** | Custom Image Builder components | 6 components (3 Linux + 3 Windows) |
| **Recipe Registry** | Declarative recipe definitions | Reads YAML recipes, outputs normalized configs |
| **Golden Image** | Image Builder pipelines | Recipe, infrastructure config, distribution config, pipeline, lifecycle policy per OS |

---

## Prerequisites

### Required Tools
- **Terraform** >= 1.5.0
- **AWS CLI** >= 2.0
- **Git** (for version control)

### AWS Account Setup

#### 1. Management Account (Source Identity)
- IAM user named `Terraform` with programmatic access
- Permissions: `sts:AssumeRole` on `TerraformDeploymentRole` in Development account

#### 2. Development Account (Build Account: 732533289325)
- **IAM Role**: `TerraformDeploymentRole` with trust policy allowing Management account
- **Permissions**: Admin or scoped permissions for EC2, Image Builder, IAM, KMS, S3, SNS, SSM
- **VPC**: Private subnet with NAT Gateway or VPC endpoints for SSM, S3, package repos
- **S3 Bucket**: For Image Builder logs (e.g., `jcp-infra-nonprod`)
- **EC2 Key Pair**: In build region (default: `MYLABKEY`)

#### 3. Target Accounts (e.g., 774133226694, 373160674113)
Each target account **must** have this IAM role deployed **once**:

```hcl
# Deploy in EACH target account (via StackSets, CloudFormation, or Terraform)
resource "aws_iam_role" "imagebuilder_distribution_cross_account" {
  name = "EC2ImageBuilderDistributionCrossAccountRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::732533289325:root" }
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

---

## Quick Start

```bash
# 1. Clone repository
git clone <repository-url>
cd b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod

# 2. Configure backend (S3 + DynamoDB)
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your S3 bucket and DynamoDB table

# 3. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (vpc_id, subnet_id, etc.)

# 4. Initialize
terraform init -backend-config=backend.hcl

# 5. Deploy in order
terraform plan -target=module.foundation
terraform apply -target=module.foundation

terraform plan -target=module.components
terraform apply -target=module.components

terraform plan
terraform apply
```

---

## Detailed Deployment Guide

### Step 1: Backend Configuration

Create `backend.hcl` in `environments/prod/`:

```hcl
# backend.hcl
bucket         = "your-terraform-state-bucket"
key            = "golden-ami-factory/prod/terraform.tfstate"
region         = "us-east-1"
# dynamodb_table = "terraform-state-lock"
use_lockfile = true
encrypt        = true
```

### Step 2: Variable Configuration

Create `terraform.tfvars` in `environments/prod/`:

```hcl
# terraform.tfvars
deployment_name = "jetstarairwaysnonprod_syd"

# Network (REQUIRED - no defaults)
vpc_id     = "vpc-0123456789abcdef0"
subnet_id  = "subnet-0123456789abcdef0"

# Optional overrides
key_pair_name           = "MYLABKEY"
log_bucket_name         = "jcp-infra-nonprod"
ebs_encrypted           = false
ebs_kms_key_alias       = "alias/aws/ebs"
stig_level              = "medium"
ami_name_prefix         = "jq-golden-ami"
ami_architecture        = "x86_64"
ami_release_version     = "1"
ssm_parameter_prefix    = "/golden-ami"

# Target accounts for cross-account sharing
target_account_ids = ["774133226694", "373160674113"]

# Instance types (cost-optimized defaults)
windows_instance_types = ["t3.large", "t3a.large"]
linux_instance_types   = ["t3.large", "t3a.large"]

# Pipeline schedule (null = manual/GitHub Actions)
pipeline_schedule_expression = null

# Retention
images_to_retain = 3
```

### Step 3: Deploy Foundation Module

```bash
terraform plan -target=module.foundation
terraform apply -target=module.foundation
```

**Resources Created:**
- `aws_iam_role.build` - EC2 instance role for build instances
- `aws_iam_instance_profile.build` - Instance profile
- `aws_security_group.build` - Build instance SG (no ingress, HTTP/HTTPS egress)
- `aws_sns_topic.builds` - Build notifications
- `aws_iam_role.lifecycle` - Lifecycle policy execution role
- `aws_iam_role.imagebuilder_execution` - Image Builder execution role

### Step 4: Deploy Components Module

```bash
terraform plan -target=module.components
terraform apply -target=module.components
```

**Resources Created (6 components with content-hashed names):**
- `jq-golden-ami-linux-ssm-agent-<hash>`
- `jq-golden-ami-linux-hardening-<hash>`
- `jq-golden-ami-linux-validate-<hash>`
- `jq-golden-ami-windows-ssm-agent-<hash>`
- `jq-golden-ami-windows-hardening-<hash>`
- `jq-golden-ami-windows-validate-<hash>`

### Step 5: Deploy Golden Image Pipelines

```bash
terraform plan
terraform apply
```

**Resources Created Per OS (5 OSes = 5 pipelines):**
- Image Recipe (immutable, content-hashed name)
- Infrastructure Configuration
- Distribution Configuration (with cross-account sharing)
- Image Pipeline (ENABLED)
- Lifecycle Policy (retain 3 newest)

---

## Adding New Target Accounts

### Method 1: Permanent Addition (Recommended)

**File to edit:** `environments/prod/variables.tf`

```hcl
variable "target_account_ids" {
  description = "Distribution accounts to share AMIs with..."
  type        = list(string)
  default     = [
    "774133226694",  # Production
    "373160674113",  # Management
    "NEW_ACCOUNT_ID_HERE"  # <-- ADD HERE
  ]
}
```

**Then deploy:**
```bash
cd environments/prod
terraform apply
```

**Prerequisites for NEW target account:**
1. Deploy the cross-account IAM role (see [Prerequisites](#3-target-accounts))
2. If using encryption: Create KMS key in target account with proper policy

### Method 2: Temporary Override (Testing)

```bash
terraform apply -var='target_account_ids=["774133226694", "373160674113", "NEW_ACCOUNT_ID"]'
```

### Method 3: CI/CD Environment Variable

```bash
export TF_VAR_target_account_ids='["774133226694", "373160674113", "NEW_ACCOUNT_ID"]'
terraform apply
```

### What Happens Automatically

After adding account and running `terraform apply`, the **next pipeline execution** will:
1. Build AMI in source account (732533289325)
2. Share AMI with new account via launch permissions
3. Create SSM parameter `/golden-ami/{os_key}/latest` in new account
4. New account can immediately consume the AMI

### Verification in Target Account

```bash
# Check SSM parameter
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1

# List shared AMIs
aws ec2 describe-images --owners 732533289325 --filters "Name=name,Values=jq-golden-ami-*" --region us-east-1
```

---

## Adding New Recipes

Recipes are defined declaratively in **YAML files** under `modules/recipe_registry/recipes/`. No Terraform code changes required.

### Current Recipes (5 OSes)

| Recipe File | OS | Display Name | Parent Image |
|-------------|-----|--------------|--------------|
| `rhel-8.yaml` | Linux | RHEL 8 | red-hat-enterprise-linux-8-x86 |
| `rhel-9.yaml` | Linux | RHEL 9 | red-hat-enterprise-linux-9-x86 |
| `rhel-10.yaml` | Linux | RHEL 10 | red-hat-enterprise-linux-10-x86 |
| `windows-2022.yaml` | Windows | Windows Server 2022 | windows-server-2022-english-full-base-x86 |
| `windows-2025.yaml` | Windows | Windows Server 2025 | windows-server-2025-english-full-base-x86 |

### Step 1: Create New Recipe YAML

**File location:** `golden-ami-factory/modules/recipe_registry/recipes/<recipe-key>.yaml`

```yaml
# Example: rhel-9-stig-high.yaml
# Golden AMI recipe for RHEL 9 with High STIG

name: "RHEL 9 Golden Image (STIG High)"
description: "Hardened RHEL 9 image with High STIG, SSM Agent, CloudWatch Agent, and validation tests"

os_family: "linux"

parent_image_arn: "${aws_managed_components_prefix}:image/red-hat-enterprise-linux-9-x86/x.x.x"
stig_component_arn: "${aws_managed_components_prefix}:component/stig-build-linux/x.x.x"
stig_level: "high"

root_volume_size: 100
root_device_name: "/dev/xvda"
ebs_encrypted: false
kms_key_arn: ""

component_chain:
  - arn: "${aws_managed_components_prefix}:component/update-linux/x.x.x"
    phase: "build"
  - arn: "${aws_managed_components_prefix}:component/aws-cli-version-2-linux/x.x.x"
    phase: "build"
  - arn: "${custom_components_arns["linux-ssm-agent"]}"
    phase: "build"
  - arn: "${aws_managed_components_prefix}:component/stig-build-linux/x.x.x"
    phase: "build"
    parameters:
      Level: "High"
  - arn: "${custom_components_arns["linux-hardening"]}"
    phase: "build"
  - arn: "${custom_components_arns["linux-validate"]}"
    phase: "test"
  - arn: "${aws_managed_components_prefix}:component/amazon-cloudwatch-agent-linux/x.x.x"
    phase: "build"
  - arn: "${aws_managed_components_prefix}:component/simple-boot-test-linux/x.x.x"
    phase: "test"

block_device_mappings: []
ami_name_suffix: "-stig-high"
distribution_regions: []
lifecycle_policy_count: 3

tags:
  Compliance: "STIG-High"
  OSFamily: "Linux"
  BaseOS: "RHEL-9"
```

### Step 2: Register in Index

**File to edit:** `golden-ami-factory/modules/recipe_registry/recipes/index.yaml`

```yaml
# Recipe Registry Index
recipes:
  - rhel-8
  - rhel-9
  - rhel-10
  - windows-2022
  - windows-2025
  - rhel-9-stig-high        # <-- ADD HERE
  # - rhel-9-cis            # Future recipes
  # - ubuntu-2204-cis
  # - amazon-linux-2023-stig-medium
  # - windows-2025-pci-dss
```

### Step 3: Enable in Terraform (Optional)

**File to edit:** `environments/prod/terraform.tfvars` or `variables.tf`

```hcl
# Enable specific recipes (empty = all from index.yaml)
enabled_recipes = [
  "rhel-8",
  "rhel-9",
  "rhel-10",
  "windows-2022",
  "windows-2025",
  "rhel-9-stig-high"    # <-- ADD HERE
]
```

### Step 4: Deploy

```bash
cd environments/prod
terraform plan
terraform apply
```

**New resources created:**
- Image Recipe: `jq-golden-ami-rhel-9-stig-high-<hash>`
- Infrastructure Configuration: `jq-golden-ami-rhel-9-stig-high`
- Distribution Configuration: `jq-golden-ami-rhel-9-stig-high`
- Image Pipeline: `jq-golden-ami-rhel-9-stig-high`
- Lifecycle Policy: `jq-golden-ami-rhel-9-stig-high`

### Recipe YAML Schema Reference

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | Yes | string | Display name for the recipe |
| `description` | Yes | string | Description |
| `os_family` | Yes | string | `linux` or `windows` |
| `parent_image_arn` | Yes | string | Base image ARN (supports `${aws_managed_components_prefix}`) |
| `stig_component_arn` | Yes | string | STIG component ARN (supports template vars) |
| `stig_level` | No | string | `low`, `medium`, `high` (default: `medium`) |
| `root_volume_size` | No | number | Root volume in GB (default: 100) |
| `root_device_name` | No | string | `/dev/xvda` (Linux) or `/dev/sda1` (Windows) |
| `ebs_encrypted` | No | bool | Enable EBS encryption (default: false) |
| `kms_key_arn` | No | string | KMS key ARN if encrypted |
| `component_chain` | Yes | list(object) | Ordered list of components |
| `block_device_mappings` | No | list | Additional block devices |
| `ami_name_suffix` | No | string | Suffix for AMI name |
| `distribution_regions` | No | list(string) | Additional regions |
| `lifecycle_policy_count` | No | number | AMIs to retain (default: 3) |
| `tags` | No | map(string) | Additional tags |

**Component Chain Object:**
```yaml
- arn: "component-arn"           # Required: component ARN
  phase: "build"                 # Required: "build" or "test"
  parameters:                    # Optional: component parameters
    ParameterName: "Value"
```

### Template Variables Available

| Variable | Description |
|----------|-------------|
| `${aws_managed_components_prefix}` | Resolves to `arn:aws:imagebuilder:region:aws` |
| `${custom_components_arns["component-key"]}` | Resolves to custom component ARN |
| `${default_stig_level}` | Default STIG level from Terraform |
| `${default_root_volume_size}` | Default volume size from Terraform |

---

## Configuration Reference

### Environment Variables (`environments/prod/variables.tf`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `deployment_name` | string | `jetstarairwaysnonprod_syd` | Deployment target key |
| `vpc_id` | string | **Required** | VPC for build instances |
| `subnet_id` | string | **Required** | Private subnet for build instances |
| `key_pair_name` | string | `MYLABKEY` | EC2 key pair name |
| `log_bucket_name` | string | `jcp-infra-nonprod` | S3 bucket for logs |
| `ebs_encrypted` | bool | `false` | Enable EBS/AMI encryption |
| `ebs_kms_key_alias` | string | `alias/aws/ebs` | KMS key alias (if encrypted) |
| `stig_level` | string | `medium` | STIG severity: low/medium/high |
| `target_account_ids` | list(string) | `["774133226694", "373160674113"]` | Cross-account sharing targets |
| `enabled_recipes` | list(string) | `[]` (all) | Recipe keys to enable |
| `pipeline_schedule_expression` | string | `null` | Cron for scheduled builds |
| `images_to_retain` | number | `3` | AMIs to retain per OS |
| `windows_instance_types` | list(string) | `["t3.large", "t3a.large"]` | Windows build instance types |
| `linux_instance_types` | list(string) | `["t3.large", "t3a.large"]` | Linux build instance types |

### Component Chain Order (Built into Recipes)

**Linux:**
1. `update-linux` → OS patches
2. `aws-cli-version-2-linux` → AWS CLI v2
3. `linux-ssm-agent` → SSM Agent (custom)
4. `stig-build-linux` → STIG hardening (AWS)
5. `linux-hardening` → Extra hardening (custom)
6. `linux-validate` → Validation tests (custom)
7. `amazon-cloudwatch-agent-linux` → CW Agent (AWS)
8. `simple-boot-test-linux` → Boot test (AWS)

**Windows:**
1. `update-windows` → OS patches
2. `aws-cli-version-2-windows` → AWS CLI v2
3. `windows-ssm-agent` → SSM Agent (custom)
4. `stig-build-windows` → STIG hardening (AWS)
5. `windows-hardening` → Extra hardening (custom)
6. `windows-validate` → Validation tests (custom)
7. `amazon-cloudwatch-agent-windows` → CW Agent (AWS)
8. `simple-boot-test-windows` → Boot test (AWS)

---

## Verification & Testing

### Check Pipeline Status

```bash
# List all pipelines
aws imagebuilder list-image-pipelines --region us-east-1 --query 'imagePipelineList[].{Name:name,Status:status,Arn:arn}'

# Get specific pipeline
aws imagebuilder get-image-pipeline --image-pipeline-arn arn:aws:imagebuilder:us-east-1:732533289325:image-pipeline/jq-golden-ami-rhel-9
```

### Trigger Manual Build

```bash
# Start pipeline execution
aws imagebuilder start-image-pipeline-execution \
  --image-pipeline-arn arn:aws:imagebuilder:us-east-1:732533289325:image-pipeline/jq-golden-ami-rhel-9

# Monitor build
aws imagebuilder get-image --image-build-version-arn <returned-arn> --query 'image.state'
```

### Verify SSM Parameters

```bash
# Source account
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1

# Target account (run in target account)
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1
```

### Verify Shared AMIs

```bash
# In target account
aws ec2 describe-images \
  --owners 732533289325 \
  --filters "Name=name,Values=jq-golden-ami-rhel-9-*" \
  --query 'Images[*].{Name:Name,ImageId:ImageId,CreationDate:CreationDate}' \
  --region us-east-1
```

### Check Build Logs

```bash
# CloudWatch Logs
aws logs tail /aws/imagebuilder/jq-golden-ami-rhel-9 --follow --region us-east-1

# S3 Logs (if configured)
aws s3 ls s3://jcp-infra-nonprod/imagebuilder-logs/jq-golden-ami-rhel-9/
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| **Build fails** | Package repo access, SSM connectivity | Check VPC endpoints/NAT Gateway; verify security group egress |
| **AMI not shared** | Invalid target account ID, missing IAM role | Verify 12-digit account ID; ensure target has `EC2ImageBuilderDistributionCrossAccountRole` |
| **KMS errors** | AWS managed key used for encryption | Use customer managed key; add cross-account permissions |
| **SSM parameter missing** | Execution role lacks permissions | Check `ssm:PutParameter` in execution role policy |
| **Profile issues** | Wrong AWS CLI profile | Use `development` profile with `source_profile = default` |

### Debug Commands

```bash
# Check Image Builder execution role permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::732533289325:role/jq-golden-ami-imagebuilder-execution-role \
  --action-names ec2:ModifyImageAttribute ssm:PutParameter \
  --resource-arns "*"

# Verify target account role exists
aws iam get-role --role-name EC2ImageBuilderDistributionCrossAccountRole --profile target-account

# Check security group rules
aws ec2 describe-security-group-rules --group-id sg-xxxxxxxx --region us-east-1
```

### Pipeline States

| State | Meaning |
|-------|---------|
| `PENDING` | Queued |
| `RUNNING` | Building |
| `BUILDING` | Component execution |
| `TESTING` | Validation tests |
| `DISTRIBUTING` | Cross-account sharing |
| `INTEGRATING` | SSM parameter creation |
| `AVAILABLE` | Success |
| `FAILED` | Check CloudWatch logs |
| `CANCELLED` | Manual cancellation |

---

## Security Considerations

### Default Configuration (Unencrypted)
- ✅ Simple cross-account sharing
- ✅ No KMS complexity
- ⚠️ AMIs unencrypted at rest

### Encrypted Configuration
```hcl
ebs_encrypted     = true
ebs_kms_key_alias = "alias/golden-ami-source-ebs"  # Customer managed key
```

**Source Key Policy Must Allow:**
- `imagebuilder.amazonaws.com` service
- All target account roots (for re-encryption)

**Target Key Policy Must Allow:**
- `imagebuilder.amazonaws.com` service
- Source account (for decrypt during copy)

### Network Security
- Build instances in **private subnet only**
- **No inbound rules** on security group
- Egress: **HTTPS (443)** for SSM/S3, **HTTP (80)** for package mirrors
- IMDSv2 enforced on build instances

### Compliance
- STIG levels: Low / Medium / High (configurable per recipe)
- Component versioning via content hash (immutable)
- Lifecycle policies prevent AMI sprawl

---

## Cleanup

### Destroy All Resources

```bash
cd golden-ami-factory/environments/prod
terraform destroy
```

### Destroy Specific OS Pipeline

```bash
# Target specific pipeline
terraform destroy -target=module.golden_image["rhel-9"]
```

### Manual Cleanup (If Needed)

```bash
# Delete shared AMIs in target accounts
aws ec2 deregister-image --image-id ami-xxxxx --region us-east-1

# Delete SSM parameters
aws ssm delete-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1

# Delete snapshots
aws ec2 delete-snapshot --snapshot-id snap-xxxxx --region us-east-1
```

---

## File Structure Summary

```
b-aws-tf-gha-aws-golden-ami-factory/
├── README.md                              # THIS FILE
├── CLAUDE.md                              # Project instructions for AI assistants
└── golden-ami-factory/
    ├── SOLUTION.md                        # Enterprise architecture design
    ├── CROSS_ACCOUNT_SHARING.md           # Cross-account sharing guide
    ├── modules/
    │   ├── foundation/                    # IAM, SG, SNS
    │   ├── components/                    # Custom components (6)
    │   ├── recipe_registry/               # Declarative recipes
    │   │   └── recipes/                   # YAML recipe definitions
    │   │       ├── index.yaml             # Recipe registry index
    │   │       ├── rhel-8.yaml
    │   │       ├── rhel-9.yaml
    │   │       ├── rhel-10.yaml
    │   │       ├── windows-2022.yaml
    │   │       └── windows-2025.yaml
    │   └── golden_image/                  # Pipeline module
    └── environments/
        └── prod/                          # Production environment
            ├── backend.hcl                # Backend config (create from example)
            ├── backend.hcl.example
            ├── terraform.tfvars           # Variables (create from example)
            ├── main.tf
            ├── locals.tf
            ├── variables.tf
            ├── outputs.tf
            ├── providers.tf
            └── versions.tf
```

---

## Support & Documentation

- **Architecture Design**: [`golden-ami-factory/SOLUTION.md`](golden-ami-factory/SOLUTION.md)
- **Cross-Account Guide**: [`golden-ami-factory/CROSS_ACCOUNT_SHARING.md`](golden-ami-factory/CROSS_ACCOUNT_SHARING.md)
<!-- This is a single-line comment 
-  **Project Instructions**: [`CLAUDE.md`](CLAUDE.md)
-->

### AWS Documentation References
- [EC2 Image Builder User Guide](https://docs.aws.amazon.com/imagebuilder/latest/userguide/)
- [Image Builder Components](https://docs.aws.amazon.com/imagebuilder/latest/userguide/components.html)
- [Cross-Account AMI Distribution](https://docs.aws.amazon.com/imagebuilder/latest/userguide/distribute-ami.html)
- [STIG Components](https://docs.aws.amazon.com/imagebuilder/latest/userguide/ib-stig.html)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | 2025-11-09 | Added recipe registry, GitOps onboarding, enterprise docs |
| 1.0 | 2025-11-06 | Initial release with 5 OS pipelines |

---

*Maintained by Platform Engineering*  
*For internal use only*