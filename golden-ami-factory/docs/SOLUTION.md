# 🏗️ Multi-Account Golden AMI Factory - Enterprise Solution Design

> **Version:** 2.2 | **Last Updated:** 2025-11-10 | **Author:** Platform Engineering  
> **Classification:** Internal - Platform Team

---

## 📋 Executive Summary

This document outlines the architecture for distributing hardened, compliant Golden AMIs from **1 source account** to **2 target accounts** (with extensibility for future accounts) using the existing Terraform-based **EC2 Image Builder** factory.

| Aspect | Current State | Target State |
|--------|--------------|--------------|
| **Distribution** | 1 source → 2 targets | 1 source → N targets (extensible) |
| **Encryption** | Disabled (AWS managed KMS) | Customer managed KMS (when enabled) |
| **Compliance** | STIG High (CIS Level 2) | Configurable per account/OS |
| **Automation** | Monthly scheduled + manual | Event-driven + scheduled |
| **AMI Versioning** | Build timestamp (default) | Optional semantic versioning |

---

## 🎯 Current Implementation Status

### ✅ What Works Today

| Feature | Status | Implementation |
|---------|--------|----------------|
| ![Cross-Account](https://img.shields.io/badge/Cross--Account-Working-brightgreen) | **Working** | Native Image Builder `target_account_ids` |
| ![SSM](https://img.shields.io/badge/SSM_Parameter-Replication-brightgreen) | **Working** | Parameters in source + all target accounts |
| ![Components](https://img.shields.io/badge/Custom_Components-6_Active-brightgreen) | **Working** | 6 components (Linux/Windows: SSM, Hardening, Validation) |
| ![Recipes](https://img.shields.io/badge/Recipe_Registry-Declarative-brightgreen) | **Working** | YAML-based with template interpolation |
| ![Lifecycle](https://img.shields.io/badge/Lifecycle_Policies-Active-brightgreen) | **Working** | Retains 3 AMIs per OS (configurable) |
| ![STIG](https://img.shields.io/badge/STIG_Compliance-High-brightgreen) | **Working** | Configurable: low/medium/high |
| ![Security](https://img.shields.io/badge/Security_Group-Drift_Free-brightgreen) | **Fixed** | Uses `aws_security_group_rule` resources |
| ![Tags](https://img.shields.io/badge/AMI_Tags-Null_Fixed-brightgreen) | **Fixed** | Tags resolve to "latest" or current date |

### 📊 Current Configuration

| Account | ID | Role | Region |
|---------|-----|------|--------|
| ![AWS](https://img.shields.io/badge/Source_Account-Development-orange) | `732533289325` | **Build Account** | `ap-southeast-2` |
| ![AWS](https://img.shields.io/badge/Target_Account-Production-blue) | `774133226694` | **Consumer** | `ap-southeast-2` |
| ![AWS](https://img.shields.io/badge/Target_Account-Management-purple) | `373160674113` | **Consumer** | `ap-southeast-2` |

**Supported Operating Systems:**
- 🐧 **Linux:** RHEL 8, RHEL 9, RHEL 10
- 🪟 **Windows:** Windows Server 2022, Windows Server 2025

---

## 🔐 Core Challenges & Solutions

### 2.1 KMS Encryption & Cross-Account Snapshot Sharing

| Challenge | Current State | Future Enhancement |
|-----------|---------------|-------------------|
| ![Key](https://img.shields.io/badge/AWS_Managed_Keys-Account_Scoped-red) | Encryption **disabled** (`ebs_encrypted = false`) | Customer managed key with cross-account policy |
| ![Lock](https://img.shields.io/badge/Cross--Account_Key_Policy-None-red) | N/A - not using encryption | Required for encrypted multi-account |
| ![Refresh](https://img.shields.io/badge/Re--Encryption_Behavior-None-red) | N/A | Works with customer managed keys |
| ![Rotate](https://img.shields.io/badge/Key_Rotation-None-red) | N/A | Need rotation strategy with alias stability |

> **💡 Current Decision:** EBS encryption is **disabled by default** to enable seamless cross-account sharing without KMS complexity. When encryption is required, a customer managed KMS key with proper cross-account policies must be created.

### 2.2 IAM & Cross-Account Permissions

| Component | Implementation |
|-----------|----------------|
| ![Shield](https://img.shields.io/badge/Image_Builder_Execution_Role-Created-brightgreen) | Foundation module with dynamic cross-account assume role permissions |
| ![Shield](https://img.shields.io/badge/Target_Account_Role-EC2ImageBuilderDistributionCrossAccountRole-brightgreen) | With `EC2ImageBuilderDistributionCrossAccountRolePolicy` |
| ![Shield](https://img.shields.io/badge/External_ID-imagebuilder--distribution-brightgreen) | Used for secure cross-account trust |

### 2.3 AMI Distribution Configuration

| Aspect | Implementation |
|--------|----------------|
| ![Target](https://img.shields.io/badge/Target_Accounts-Static_List-blue) | `target_account_ids` variable (easily extensible) |
| ![Globe](https://img.shields.io/badge/Regions-Single_Region-blue) | Source region only - multi-region planned |
| ![Tag](https://img.shields.io/badge/AMI_Naming-Patternized-blue) | `{prefix}-{os}-{arch}-{YYMM}[.{release}]-{buildDate}` |
| ![Share](https://img.shields.io/badge/Launch_Permissions-Auto_Managed-blue) | Automatically managed by Image Builder |

### 2.4 SSM Parameter Store Replication

- ✅ **Source Account:** `/golden-ami/{os_key}/latest`
- ✅ **Target Accounts:** Same parameter name, account-specific AMI ID
- ✅ **Data Type:** `aws:ec2:image` for CloudFormation compatibility

### 2.5 Lifecycle Management

- ✅ **Retention:** 3 newest AMIs per OS (configurable via `images_to_retain`)
- ✅ **Execution:** Source account only
- ⚠️ **Future:** Target account cleanup not yet implemented

### 2.6 Networking & Connectivity

| Component | Current State |
|-----------|---------------|
| ![VPC](https://img.shields.io/badge/Build_VPC-Single_Account-orange) | Single VPC in source account |
| ![Egress](https://img.shields.io/badge/Egress-HTTP/HTTPS-orange) | Via security group rules |
| ![Endpoints](https://img.shields.io/badge/VPC_Endpoints-Assumed-orange) | For SSM, S3, package repos |

### 2.7 Security & Compliance

| Feature | Implementation |
|---------|----------------|
| ![STIG](https://img.shields.io/badge/STIG_Level-Configurable-brightgreen) | low/medium/high (default: high) |
| ![Hash](https://img.shields.io/badge/Component_Versioning-Content_Hashed-brightgreen) | Immutable via content hash |
| ![IMDS](https://img.shields.io/badge/IMDSv2-Enforced-brightgreen) | On all build instances |
| ![Lock](https://img.shields.io/badge/Encryption-Optional-blue) | Disabled by default |
| ![Tags](https://img.shields.io/badge/AMI_Tags-Null_Safe-brightgreen) | Tags never null; resolve to "latest" or date |

---

## 🏛️ Architecture Diagram

```mermaid
graph TB
    subgraph SA[🟠 SOURCE ACCOUNT - Development (732533289325)]
        TF[📦 Terraform State<br/>S3 + DynamoDB]
        IB[🏗️ Image Builder Pipelines]
        IAM[🛡️ IAM Roles<br/>• Build Instance Role<br/>• Lifecycle Role<br/>• ImageBuilder Execution Role]
        DIST[📤 Distribution Configuration]
        
        TF --> IB
        IB --> DIST
        IB --> IAM
    end
    
    DIST -->|Cross-Account Sharing| TA1[🔵 TARGET 1 - Production (774133226694)]
    DIST -->|Cross-Account Sharing| TA2[🟣 TARGET 2 - Management (373160674113)]
    DIST -->|Extensible| TA3[⚪ TARGET N - Future Accounts]
    
    subgraph TA1
        IAM1[🛡️ EC2ImageBuilderDistributionCrossAccountRole]
        AMI1[📦 Shared AMIs]
        SSM1[📋 SSM Parameter<br/>/golden-ami/{os}/latest]
        IAM1 --> AMI1
        IAM1 --> SSM1
    end
    
    subgraph TA2
        IAM2[🛡️ EC2ImageBuilderDistributionCrossAccountRole]
        AMI2[📦 Shared AMIs]
        SSM2[📋 SSM Parameter<br/>/golden-ami/{os}/latest]
        IAM2 --> AMI2
        IAM2 --> SSM2
    end
    
    subgraph TA3
        IAM3[🛡️ EC2ImageBuilderDistributionCrossAccountRole]
        AMI3[📦 Shared AMIs]
        SSM3[📋 SSM Parameter<br/>/golden-ami/{os}/latest]
        IAM3 --> AMI3
        IAM3 --> SSM3
    end
```

---

## ⚙️ Implementation Details

### 4.1 Target Account Bootstrap (Required Once Per Target)

Each target account must deploy this IAM role **one time**:

```hcl
# In TARGET ACCOUNT (run once):
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

### 4.2 Source Account Configuration

**File:** `environments/prod/variables.tf`

```hcl
variable "target_account_ids" {
  description = "Distribution accounts to share AMIs with"
  type        = list(string)
  default     = ["774133226694", "373160674113"]  # Add more accounts here
}
```

**File:** `modules/foundation/main.tf` - Dynamic cross-account permissions

```hcl
dynamic "statement" {
  for_each = length(var.target_account_ids) > 0 ? [1] : []
  content {
    sid     = "AllowAssumeDistributionCrossAccountRole"
    actions = ["sts:AssumeRole"]
    resources = [for account_id in var.target_account_ids : 
      "arn:${data.aws_partition.current.partition}:iam::${account_id}:role/EC2ImageBuilderDistributionCrossAccountRole"]
  }
}
```

### 4.3 Distribution Configuration

**File:** `modules/golden_image/main.tf`

```hcl
locals {
  # Resolved values for tags (never null/empty to avoid AWS tag validation errors)
  ami_date_token     = var.ami_date_token != null ? var.ami_date_token : formatdate(var.ami_date_format, plantimestamp())
  ami_release_version = var.ami_release_version != "" ? var.ami_release_version : "latest"
  
  # AMI name with optional release version
  ami_name = var.ami_release_version != "" 
    ? "${var.ami_name_prefix}-${var.ami_os_code}-${var.ami_architecture}-${local.ami_date_token}.${var.ami_release_version}-{{ imagebuilder:buildDate }}"
    : "${var.ami_name_prefix}-${var.ami_os_code}-${var.ami_architecture}-${local.ami_date_token}-{{ imagebuilder:buildDate }}"
  ami_name_tag = var.ami_release_version != ""
    ? "${var.ami_name_prefix}-${var.ami_os_code}-${var.ami_architecture}-${local.ami_date_token}.${var.ami_release_version}"
    : "${var.ami_name_prefix}-${var.ami_os_code}-${var.ami_architecture}-${local.ami_date_token}"
}

distribution {
  region = data.aws_region.current.region

  ami_distribution_configuration {
    name               = local.ami_name
    target_account_ids = length(var.target_account_ids) > 0 ? var.target_account_ids : null
    ami_tags = merge(var.tags, {
      Name        = local.ami_name_tag
      OS          = var.os_key
      DateToken   = local.ami_date_token
      Release     = local.ami_release_version
      GoldenImage = var.os_key
    })
  }

  # Parameter in build account
  ssm_parameter_configuration {
    parameter_name = var.ssm_parameter_name
    data_type      = "aws:ec2:image"
  }

  # Parameter in EACH target account
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

---

## 🚀 Extensibility - Adding New Accounts

### Quick Add (Current Method)

```bash
# 1. Edit variables.tf or terraform.tfvars
target_account_ids = ["774133226694", "373160674113", "NEW_ACCOUNT_ID"]

# 2. Apply
cd environments/prod
terraform apply

# 3. Deploy bootstrap role in NEW target account (one-time)
# 4. Next pipeline run automatically shares to new account
```

### Planned Enhancement: `accounts.yaml` (Future)

For larger scale (10+ accounts), migrate to declarative configuration:

```yaml
# accounts.yaml
accounts:
  - account_id: "999999999999"
    account_name: "new-workload"
    account_alias: "new-wl"
    regions:
      - ap-southeast-2
    ami_distribution:
      enabled: true
      retention_count: 3
      stig_level: "high"
```

---

## 🗺️ Implementation Roadmap

| Phase | Status | Description |
|-------|--------|-------------|
| **Phase 1** | ✅ **Complete** | Stable multi-account (2 targets), SSM replication, lifecycle policies, SG egress fix, Recipe registry, Tag null fix |
| **Phase 2** | 🔄 **Planned** | Encryption support: customer managed KMS, cross-account key policies, encrypted distribution |
| **Phase 3** | 📋 **Future** | Dynamic configuration: `accounts.yaml` schema, per-account retention/CIS overrides |
| **Phase 4** | 📋 **Future** | Observability: Central EventBridge, CloudWatch dashboards, build failure alerting |
| **Phase 5** | 📋 **Future** | Operations: Drift detection, automated rollback, cost allocation tags, runbooks |

---

## 💰 Cost Estimation (3 Accounts)

| Component | Monthly Cost (Est.) |
|-----------|---------------------|
| 💾 AMI Storage (3 accts × 5 OS × 3 retained × ~5GB) | ~$35 |
| 📸 Snapshot Copy (cross-account) | ~$12 |
| 🔐 KMS Keys (if encrypted) | ~$3 |
| 🏗️ Image Builder Build (5 OS × monthly) | ~$200 |
| 📊 CloudWatch/EventBridge | ~$15 |
| **Total Estimated** | **~$265/mo** |

---

## 🔐 Security Checklist

- ✅ Build instances in private subnet, no inbound access
- ✅ IMDSv2 enforced
- ✅ Least-privilege IAM roles
- ✅ ExternalId for cross-account trust
- ✅ STIG hardening (configurable level)
- ✅ Component immutability via content hashing
- ✅ AMI tags never null (resolved to "latest" or date)
- ⬜ KMS encryption (when enabled)
- ⬜ VPC endpoints for KMS/S3/SSM
- ⬜ CloudTrail logging in all accounts

---

## 📁 File Structure

```
golden-ami-factory/
├── 📄 CONFIGURABLE_VALUES.md           # All tfvars reference
├── 📄 SOLUTION.md                      # This file
├── 📄 CROSS_ACCOUNT_SHARING.md         # Cross-account guide
├── 📁 modules/
│   ├── 📁 components/                  # Custom Image Builder components
│   ├── 📁 foundation/                  # IAM, SG, SNS
│   ├── 📁 golden_image/                # Image Builder pipelines
│   └── 📁 recipe_registry/             # YAML-based recipes
└── 📁 environments/
    └── 📁 prod/                        # Production config
        ├── 📄 variables.tf             # target_account_ids here
        ├── 📄 locals.tf
        ├── 📄 main.tf
        └── 📄 terraform.tfvars         # Single source of truth
```

---

## 📝 Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-11-06 | Disable EBS encryption by default | Simplifies cross-account sharing; AWS managed keys don't support cross-account |
| 2025-11-06 | Use `aws_security_group_rule` for egress | Avoids perpetual drift with `aws_vpc_security_group_egress_rule` |
| 2025-11-06 | Static `target_account_ids` list | Simple, works for 2-5 accounts; migrate to YAML when needed |
| 2025-11-06 | Single region (ap-southeast-2) | Current requirement; multi-region planned |
| 2025-11-06 | STIG default: high | Enterprise compliance baseline |
| 2025-11-10 | AMI versioning defaults to build timestamp | Avoids hardcoded version; allows optional semantic versioning |
| 2025-11-10 | AMI tags resolve null values | Prevents "Tag value cannot be null" distribution errors |
| 2025-11-11 | RHEL root_volume_size omitted | Uses parent AMI default size; avoids additional 100GB volume |

## ✅ Next Steps

1. **Monitor** - Verify pipeline runs and cross-account sharing
2. **Validate** - Check SSM parameters in all 3 accounts
3. **Document** - Update runbooks for operations team
4. **Plan** - Evaluate encryption requirements for compliance
5. **Scale** - When adding >5 accounts, implement `accounts.yaml`

---

<div align="center">

**📄 Document Version: 2.2**  
**👤 Author: Platform Engineering**  
**📅 Last Updated: 2025-11-10**  
**🏷️ Classification: Internal - Platform Team**

</div>