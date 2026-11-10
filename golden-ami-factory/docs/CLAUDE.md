# 🏗️ AWS Golden AMI Factory - Project Instructions

> **Version:** 2.1 | **Last Updated:** 2025-11-09 | **Author:** Platform Engineering

---

## 📖 Project Overview

This is a **Terraform-based solution** for building hardened, compliant Golden AMIs using **AWS EC2 Image Builder**, with native cross-account distribution capabilities.

### 🎯 Supported Platforms

| OS Family | Versions | Compliance |
|-----------|----------|------------|
| 🐧 **Linux** | RHEL 8, RHEL 9, RHEL 10 | STIG + CIS Level 2 |
| 🪟 **Windows** | Server 2022, Server 2025 | STIG + CIS Level 2 |

### ✨ Key Features

- ✅ **Native Cross-Account Sharing** - No separate Terraform state
- ✅ **Declarative Recipes** - YAML-based with GitOps workflow
- ✅ **Automated SSM Replication** - Parameters in source + all targets
- ✅ **Lifecycle Management** - Configurable AMI retention
- ✅ **Immutable Components** - Content-hashed versioning
- ✅ **Single Source of Truth** - All config in `terraform.tfvars`

---

## 📁 Repository Structure

```
b-aws-tf-gha-aws-golden-ami-factory/
├── 📄 CLAUDE.md                      # This file
├── 📄 SOLUTION.md                    # Enterprise solution design
├── 📄 CROSS_ACCOUNT_SHARING.md       # Cross-account guide
├── 📄 CONFIGURABLE_VALUES.md         # All tfvars reference
├── 📁 golden-ami-factory/
│   ├── 📄 .gitignore
│   ├── 📁 modules/
│   │   ├── 📁 components/            # Custom Image Builder components
│   │   │   ├── 📄 main.tf
│   │   │   ├── 📄 variables.tf
│   │   │   ├── 📄 outputs.tf
│   │   │   └── 📁 files/             # YAML component definitions
│   │   │       ├── 📄 linux-hardening.yml
│   │   │       ├── 📄 linux-ssm-agent.yml
│   │   │       ├── 📄 linux-validate.yml
│   │   │       ├── 📄 windows-hardening.yml
│   │   │       ├── 📄 windows-ssm-agent.yml
│   │   │       └── 📄 windows-validate.yml
│   │   ├── 📁 foundation/            # Foundation IAM/Networking
│   │   │   ├── 📄 main.tf
│   │   │   ├── 📄 variables.tf
│   │   │   └── 📄 outputs.tf
│   │   ├── 📁 golden_image/          # Image Builder pipelines
│   │   │   ├── 📄 main.tf
│   │   │   ├── 📄 variables.tf
│   │   │   └── 📄 outputs.tf
│   │   └── 📁 recipe_registry/       # Declarative recipes (YAML)
│   │       ├── 📄 main.tf
│   │       ├── 📄 outputs.tf
│   │       ├── 📄 variables.tf
│   │       └── 📁 recipes/
│   │           ├── 📄 index.yaml
│   │           ├── 📄 rhel-8.yaml
│   │           ├── 📄 rhel-9.yaml
│   │           ├── 📄 rhel-10.yaml
│   │           ├── 📄 windows-2022.yaml
│   │           └── 📄 windows-2025.yaml
│   └── 📁 environments/
│       └── 📁 prod/                  # Production environment
│           ├── 📄 backend.hcl
│           ├── 📄 backend.hcl.example
│           ├── 📄 backend.tf
│           ├── 📄 locals.tf
│           ├── 📄 main.tf
│           ├── 📄 outputs.tf
│           ├── 📄 providers.tf
│           ├── 📄 terraform.tfvars   # ⭐ SINGLE SOURCE OF TRUTH
│           ├── 📄 variables.tf
│           └── 📄 versions.tf
```

---

## 🔧 Key Modules

### 1. Foundation Module (`modules/foundation`)

Creates IAM roles and networking for Image Builder:

| Resource | Purpose |
|----------|---------|
| ![IAM](https://img.shields.io/badge/Build_Instance_Role-aws__iam__role.build-blue) | EC2 role with SSM, Image Builder, S3 log write |
| ![IAM](https://img.shields.io/badge/Build_Instance_Profile-aws__iam__instance__profile.build-blue) | Instance profile for build instances |
| ![SG](https://img.shields.io/badge/Security_Group-aws__security__group.build-orange) | No ingress, HTTP/HTTPS egress only |
| ![SNS](https://img.shields.io/badge/SNS_Topic-aws__sns__topic.builds-yellow) | Build notifications with email subscriptions |
| ![IAM](https://img.shields.io/badge/Lifecycle_Role-aws__iam__role.lifecycle-blue) | For Image Builder lifecycle policies |
| ![IAM](https://img.shields.io/badge/Execution_Role-aws__iam__role.imagebuilder__execution-blue) | Distribution, SSM params, cross-account sharing |

### 2. Components Module (`modules/components`)

Creates **6 custom Image Builder components** with content-hashed names for immutable versioning:

| Component | Platform | Purpose |
|-----------|----------|---------|
| ![Windows](https://img.shields.io/badge/windows--ssm--agent-Windows-blue) | Windows | Checks/reports SSM Agent version |
| ![Windows](https://img.shields.io/badge/windows--hardening-Windows-blue) | Windows | Extra hardening post-STIG |
| ![Windows](https://img.shields.io/badge/windows--validate-Windows-blue) | Windows | Baseline validation tests |
| ![Linux](https://img.shields.io/badge/linux--ssm--agent-Linux-green) | Linux | Installs/upgrades SSM Agent on RHEL |
| ![Linux](https://img.shields.io/badge/linux--hardening-Linux-green) | Linux | Extra hardening post-STIG |
| ![Linux](https://img.shields.io/badge/linux--validate-Linux-green) | Linux | Baseline validation tests |

> **Note:** CloudWatch Agent uses AWS-managed components (no agent configuration applied)

### 3. Recipe Registry Module (`modules/recipe_registry`)

Declarative recipe definitions using YAML files:

- 📖 Reads recipes from `modules/recipe_registry/recipes/`
- 🔧 Supports template interpolation for AWS-managed & custom component ARNs
- 📤 Outputs normalized recipe configurations for `golden_image` module
- 🔄 Enables GitOps-style recipe management without Terraform code changes

### 4. Golden Image Module (`modules/golden_image`)

Creates complete Image Builder pipeline per OS recipe:

| Resource | Purpose |
|----------|---------|
| ![Recipe](https://img.shields.io/badge/Image_Recipe-aws__imagebuilder__image__recipe-purple) | Parent image + component chain + block device mapping |
| ![Infra](https://img.shields.io/badge/Infrastructure_Config-aws__imagebuilder__infrastructure__configuration-purple) | Instance types, subnet, SG, key pair, logging |
| ![Dist](https://img.shields.io/badge/Distribution_Config-aws__imagebuilder__distribution__configuration-purple) | AMI naming, **cross-account sharing**, SSM parameters |
| ![Pipeline](https://img.shields.io/badge/Image_Pipeline-aws__imagebuilder__image__pipeline-purple) | Links recipe + infra + distribution + execution role |
| ![Lifecycle](https://img.shields.io/badge/Lifecycle_Policy-aws__imagebuilder__lifecycle__policy-purple) | Retains N newest AMIs (default: 3) |

---

## ⚙️ Environment Configuration (prod)

### 📋 All Variables Defined in `terraform.tfvars`

The **single source of truth** for all environment-specific configuration.

#### 🎯 Deployment Targets
```hcl
deployments = {
  jetstarairwaysnonprod_syd = {
    account_name = "Development"
    account_id   = "732533289325"
    aws_region   = "ap-southeast-2"
  }
}
deployment_name = "jetstarairwaysnonprod_syd"
```

#### 🌐 Network Configuration
```hcl
vpc_id    = "vpc-09cf7e58fed19e679"
subnet_id = "subnet-0dec91c430f1e51e7"
```

#### 🏷️ Project Metadata & Tags
```hcl
project = "jq-golden-ami"
common_tags = {
  CostCentre  = "579087"
  CreatedBy   = "DL-TechInfraCloud@singhworld.com"
  Environment = "Production"
  DeployedBy  = "IAC using Terraform"
  Owner       = "DL-TechInfraCloud@singhworld.com"
  ProtectedBy = "Tech-Infra-Cloud@singhworld.com"
}
extra_tags = {}
```

#### 🖥️ EC2 Infrastructure
```hcl
key_pair_name = "MYLABKEY"
log_bucket_name = ""
```

#### 🔐 EBS Encryption
```hcl
ebs_encrypted = false
ebs_kms_key_alias = "alias/aws/ebs"
```

#### 🏷️ AMI Naming Convention
```hcl
ami_name_prefix = "jq-golden-ami"
ami_architecture = "x86_64"
ami_date_format = "YYMM"
ami_date_token = null
ami_release_version = "1"
ssm_parameter_prefix = "/golden-ami"
```

#### 🛡️ Compliance & Hardening
```hcl
stig_level = "high"
```

#### 📋 Recipe Selection
```hcl
enabled_recipes = ["rhel-8", "rhel-9", "rhel-10", "windows-2022", "windows-2025"]
enabled_os = []  # Legacy
```

#### ⚙️ Default Recipe Settings
```hcl
default_root_volume_size = 100
default_lifecycle_policy_count = 3
default_stig_level = "high"
```

#### 🔄 Cross-Account AMI Sharing
```hcl
target_account_ids = ["774133226694", "373160674113"]
```

#### 💻 Instance Types
```hcl
windows_instance_types = ["t3.large", "t3a.large"]
linux_instance_types   = ["t3.large", "t3a.large"]
```

#### ⏰ Pipeline Scheduling
```hcl
pipeline_schedule_expression = "cron(0 3 1 * ? *)"
schedule_timezone = "Australia/Sydney"
```

#### 🧪 Test & Lifecycle
```hcl
test_timeout_minutes = 120
images_to_retain = 2
```

#### 🔧 Advanced Settings
```hcl
linux_root_device_name = "/dev/xvda"
windows_root_device_name = "/dev/sda1"
install_cloudwatch_agent = true
enable_boot_test = true
enable_stig = true
component_version = "1.0.0"
```

---

## 📦 Component Chain Order

### 🐧 Linux (RHEL 8/9/10)

| Order | Component | Type | Phase |
|-------|-----------|------|-------|
| 1 | `update-linux` | AWS Managed | Build |
| 2 | `aws-cli-version-2-linux` | AWS Managed | Build |
| 3 | `linux-ssm-agent` | **Custom** | Build |
| 4 | `stig-build-linux` | AWS Managed | Build |
| 5 | `linux-hardening` | **Custom** | Build |
| 6 | `linux-validate` | **Custom** | Test |
| 7 | `amazon-cloudwatch-agent-linux` | AWS Managed | Build |
| 8 | `simple-boot-test-linux` | AWS Managed | Test |

### 🪟 Windows (Server 2022/2025)

| Order | Component | Type | Phase |
|-------|-----------|------|-------|
| 1 | `update-windows` | AWS Managed | Build |
| 2 | `aws-cli-version-2-windows` | AWS Managed | Build |
| 3 | `windows-ssm-agent` | **Custom** | Build |
| 4 | `stig-build-windows` | AWS Managed | Build |
| 5 | `windows-hardening` | **Custom** | Build |
| 6 | `windows-validate` | **Custom** | Test |
| 7 | `amazon-cloudwatch-agent-windows` | AWS Managed | Build |
| 8 | `simple-boot-test-windows` | AWS Managed | Test |

---

## 🔄 Cross-Account AMI Sharing (Native)

> **No separate `ami_sharing` environment needed.** Sharing is configured in `modules/golden_image/main.tf` distribution configuration.

```hcl
distribution {
  ami_distribution_configuration {
    target_account_ids = var.target_account_ids  # Native Image Builder sharing
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
```

### Pipeline Execution Flow

1. 🏗️ **AMI Built** in source account (732533289325)
2. 🤝 **AMI Shared** with all `target_account_ids`
3. 📋 **SSM Parameter** `/golden-ami/{os_key}/latest` created in:
   - Source account
   - Each target account (same name, account-specific AMI ID)
4. 🗑️ **Lifecycle Policy** manages retention in source account

### To Add Accounts
```bash
# Update terraform.tfvars
target_account_ids = ["774133226694", "373160674113", "NEW_ACCOUNT_ID"]

# Apply
terraform apply

# Next pipeline run shares automatically
```

---

## 🚀 Deployment Workflow

```bash
cd golden-ami-factory/environments/prod

# 1. Initialize with backend config
terraform init -backend-config=backend.hcl

# 2. Deploy foundation (IAM, SG, SNS)
terraform plan -target=module.foundation
terraform apply -target=module.foundation

# 3. Deploy custom components
terraform plan -target=module.components
terraform apply -target=module.components

# 4. Deploy golden image pipelines
terraform plan
terraform apply
```

---

## 🔄 GitHub Actions Integration

**Workflow file:** `.github/workflows/build-golden-ami.yml` (to be created)

| Trigger | Schedule |
|---------|----------|
| 📅 **Monthly** | 1st at 03:00 UTC |
| 🖱️ **Manual** | `workflow_dispatch` |

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM Role ARN for deployment |
| `AWS_REGION` | e.g., `ap-southeast-2` |

---

## 🔑 Key Technical Details

### 🔐 EBS Encryption (Optional)

| Setting | Value |
|---------|-------|
| Controlled by | `var.ebs_encrypted` (bool, default: false) |
| When enabled | Requires `ebs_kms_key_alias` for customer-managed KMS key |
| KMS key must allow | `imagebuilder.amazonaws.com` service |
| Cross-account | Target accounts need KMS access for encrypted AMIs |

### 🔒 Image Recipe Immutability

Recipes use content hash in name:
```
substr(sha1(jsonencode([
  parent_image_arn, 
  component_arns, 
  stig_level, 
  root_volume_size, 
  ebs_encrypted, 
  kms_key_arn
])), 0, 8)
```
**Any change creates a new recipe** instead of version clash.

### 🏢 AWS Account Architecture

| Account | ID | Purpose |
|---------|-----|---------|
| ![Management](https://img.shields.io/badge/Management-373160674113-purple) | `373160674113` | Source identity, IAM user "Terraform" |
| ![Development](https://img.shields.io/badge/Development-732533289325-orange) | `732533289325` | Golden AMI Factory, TerraformDeploymentRole |
| ![Production](https://img.shields.io/badge/Production-774133226694-blue) | `774133226694` | Future AMI consumption (target account) |

### 🔐 Authentication Flow

```
1. Terraform uses AWS CLI `development` profile
2. `development` profile assumes `TerraformDeploymentRole` in Development account
3. Source credentials in `default` profile (Management account)
```

---

## ✅ Prerequisites

- Terraform >= 1.5.0
- AWS CLI with `development` profile configured
- Existing VPC with private subnet + NAT Gateway/VPC endpoints
- S3 bucket for Image Builder logs
- EC2 Key Pair in build region
- IAM permissions: EC2, Image Builder, IAM, KMS, S3, SNS, SSM

---

## 🔍 Verification Commands

```bash
# Check SSM parameter (in any account)
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region ap-southeast-2

# Check shared AMIs (in target account)
aws ec2 describe-images --owners 732533289325 --filters "Name=name,Values=jq-golden-ami-*"

# Trigger pipeline manually
aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <arn>

# Check pipeline status
aws imagebuilder get-image --image-build-version-arn <arn> --query 'image.state'
```

---

## 🐛 Common Issues & Troubleshooting

| Issue | Solution |
|-------|----------|
| **Build Failures** | Check CloudWatch Logs `/aws/imagebuilder/<pipeline-name>` or S3 logs bucket |
| **AMI Not Shared** | Verify `target_account_ids` are valid 12-digit IDs; check launch permissions |
| **KMS Errors** | Ensure customer-managed key allows `imagebuilder.amazonaws.com`; target accounts need KMS access |
| **AWS CLI Profile Issues** | Ensure `development` profile uses `source_profile = default` (not `management`) |
| **SG Egress Drift** | Fixed by using `aws_security_group_rule` instead of `aws_vpc_security_group_egress_rule` |

---

## 🔐 Security Considerations

- 🔓 **Default:** No encryption (easy cross-account sharing)
- 🔒 **With encryption:** Requires customer-managed KMS key with cross-account permissions
- 🌐 **Build instances** in private subnet, no inbound access
- 🛡️ **Least-privilege IAM roles** for Image Builder, build instances, lifecycle
- ⚙️ **Configurable STIG compliance** level (Low/Medium/High)

---

## 🧹 Cleanup

```bash
cd golden-ami-factory/environments/prod
terraform destroy
```

---

## 📚 Related Documentation

| Document | Description |
|----------|-------------|
| 📄 [SOLUTION.md](SOLUTION.md) | Enterprise solution design |
| 📄 [CROSS_ACCOUNT_SHARING.md](CROSS_ACCOUNT_SHARING.md) | Cross-account sharing guide |
| 📄 [CONFIGURABLE_VALUES.md](CONFIGURABLE_VALUES.md) | All tfvars reference |

---

<div align="center">

**📄 Document Version: 2.1**  
**👤 Author: Platform Engineering**  
**📅 Last Updated: 2025-11-09**

</div>