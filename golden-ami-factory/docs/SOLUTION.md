# Multi-Account Golden AMI Factory - Enterprise Solution Design

## Executive Summary

This document outlines the architecture for distributing golden AMIs from **1 source account** to **2 target accounts** (with extensibility for future accounts) using the existing Terraform-based EC2 Image Builder factory.

**Current State**: Multi-account deployment using AWS managed KMS key (`alias/aws/ebs`) with no encryption  
**Target State**: 3-account distribution (1 source + 2 targets) with enterprise-grade security, operations, and extensibility  
**Architecture Pattern**: Hub-and-spoke with declarative target account configuration

---

## 1. Current Implementation Status

### 1.1 What Works Today

| Feature | Status | Details |
|---------|--------|---------|
| **Cross-account AMI sharing** | ✅ Working | Native Image Builder `target_account_ids` |
| **SSM parameter replication** | ✅ Working | Parameters created in source + target accounts |
| **Custom components** | ✅ Working | 6 components (Linux/Windows hardening, SSM, validation) |
| **Recipe registry** | ✅ Working | YAML-based declarative recipes |
| **Lifecycle policies** | ✅ Working | Retains 3 AMIs per OS |
| **STIG compliance** | ✅ Working | Configurable level (default: high) |
| **Security group egress** | ✅ Fixed | Uses `aws_security_group_rule` to avoid drift |

### 1.2 Current Configuration

**Source Account**: 732533289325 (Development) - **ap-southeast-2**  
**Target Accounts**: 
- 774133226694 (Production)
- 373160674113 (Management)

**OS Support**: RHEL 8, RHEL 9, RHEL 10, Windows Server 2022, Windows Server 2025

---

## 2. Core Challenges & Solutions

### 2.1 KMS Encryption & Cross-Account Snapshot Sharing

| Challenge | Current State | Future Enhancement |
|-----------|---------------|-------------------|
| **AWS managed keys (`alias/aws/ebs`) are account-scoped** | Encryption disabled (default: false) | Customer managed key with cross-account policy |
| **No cross-account key policy on AWS managed keys** | N/A - not using encryption | Required for encrypted multi-account |
| **Image Builder re-encryption behavior** | N/A | Will work with customer managed keys |
| **Key rotation & lifecycle** | N/A | Need key rotation strategy with alias stability |

**Current Decision**: EBS encryption is **disabled by default** (`ebs_encrypted = false`) to enable seamless cross-account sharing without KMS complexity. When encryption is needed, a customer managed KMS key with proper cross-account policies must be created.

### 2.2 IAM & Cross-Account Permissions

| Component | Implementation |
|-----------|----------------|
| **Image Builder execution role** | Created in foundation module with dynamic cross-account assume role permissions |
| **Target account role** | `EC2ImageBuilderDistributionCrossAccountRole` with `EC2ImageBuilderDistributionCrossAccountRolePolicy` |
| **External ID** | Used for secure cross-account trust |

### 2.3 AMI Distribution Configuration

| Aspect | Implementation |
|--------|----------------|
| **Target accounts** | Static list in `target_account_ids` variable (easily extensible) |
| **Regions** | Single region (source region only) - multi-region planned |
| **AMI naming** | Pattern: `{prefix}-{os}-{arch}-{YYMM}.{release}-{buildDate}` |
| **Launch permissions** | Automatically managed by Image Builder |

### 2.4 SSM Parameter Store Replication

- ✅ Parameters created in source account: `/golden-ami/{os_key}/latest`
- ✅ Parameters created in each target account with same name, account-specific AMI ID
- ✅ Uses `aws:ec2:image` data type for CloudFormation compatibility

### 2.5 Lifecycle Management

- ✅ Lifecycle policy retains 3 newest AMIs per OS (configurable via `images_to_retain`)
- ✅ Runs in source account only
- ⚠️ Target account cleanup not implemented (future enhancement)

### 2.6 Networking & Connectivity

| Component | Current State |
|-----------|---------------|
| **Build VPC/Subnet** | Single VPC in source account |
| **Egress** | HTTP/HTTPS via security group rules |
| **VPC Endpoints** | Assumed available for SSM, S3, package repos |

### 2.7 Security & Compliance

| Feature | Implementation |
|---------|----------------|
| **STIG Level** | Configurable (low/medium/high) - default: high |
| **Component Versioning** | Content-hashed names for immutability |
| **IMDSv2** | Enforced on build instances |
| **Encryption** | Optional (disabled by default) |

---

## 3. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SOURCE ACCOUNT (Build Account)                      │
│  Account: 732533289325  Region: ap-southeast-2                             │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────┐  │
│  │  Terraform State │    │  Image Builder   │    │  IAM Roles           │  │
│  │  (S3 + DynamoDB) │───▶│  Pipelines       │───▶│  - Build Instance    │  │
│  └──────────────────┘    └────────┬─────────┘    │  - Lifecycle         │  │
│                                    │              │  - ImageBuilder Exec │  │
│                                    ▼              └──────────────────────┘  │
│                         ┌──────────────────┐                                │
│                         │  Distribution    │                                │
│                         │  Configuration   │                                │
│                         └────────┬─────────┘                                │
└─────────────────────────────────┼──────────────────────────────────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  TARGET ACCT 1  │    │  TARGET ACCT 2  │    │  TARGET ACCT N  │
│  774133226694   │    │  373160674113   │    │  (Future)       │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ IAM Role  │  │    │  │ IAM Role  │  │    │  │ IAM Role  │  │
│  │ (Trust)   │  │    │  │ (Trust)   │  │    │  │ (Trust)   │  │
│  └─────┬─────┘  │    │  └─────┬─────┘  │    │  └─────┬─────┘  │
│        │        │    │        │        │    │        │        │
│  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │
│  │ Shared    │  │    │  │ Shared    │  │    │  │ Shared    │  │
│  │ AMIs      │  │    │  │ AMIs      │  │    │  │ AMIs      │  │
│  └─────┬─────┘  │    │  └─────┬─────┘  │    │  └─────┬─────┘  │
│        │        │    │        │        │    │        │        │
│  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │
│  │ SSM Param │  │    │  │ SSM Param │  │    │  │ SSM Param │  │
│  │ (Latest)  │  │    │  │ (Latest)  │  │    │  │ (Latest)  │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## 4. Implementation Details

### 4.1 Target Account Bootstrap (Required Once Per Target)

Each target account must have this role deployed:

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

**File**: `environments/prod/variables.tf`

```hcl
variable "target_account_ids" {
  description = "Distribution accounts to share AMIs with"
  type        = list(string)
  default     = ["774133226694", "373160674113"]  # Add more here
}
```

**File**: `modules/foundation/main.tf` - Dynamic cross-account permissions

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

**File**: `modules/golden_image/main.tf`

```hcl
distribution {
  region = data.aws_region.current.region

  ami_distribution_configuration {
    name               = local.ami_name
    target_account_ids = length(var.target_account_ids) > 0 ? var.target_account_ids : null
    ami_tags = merge(var.tags, {
      Name        = local.ami_name_tag
      OS          = var.os_key
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

## 5. Extensibility - Adding New Accounts

### 5.1 Quick Add (Current Method)

```bash
# 1. Edit variables.tf
default = ["774133226694", "373160674113", "NEW_ACCOUNT_ID"]

# 2. Apply
terraform apply

# 3. Deploy bootstrap role in NEW target account (one-time)
# 4. Next pipeline run automatically shares to new account
```

### 5.2 Planned Enhancement: accounts.yaml (Future)

For larger scale (10+ accounts), migrate to declarative `accounts.yaml`:

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

## 6. Implementation Roadmap

### Phase 1: Current - Stable Multi-Account ✅
- [x] Cross-account sharing with 2 target accounts
- [x] SSM parameter replication
- [x] Lifecycle policies
- [x] Security group egress fix
- [x] Recipe registry with YAML

### Phase 2: Encryption Support (When Needed)
- [ ] Create customer managed KMS key in source account
- [ ] Add cross-account key policy for target accounts
- [ ] Create target account KMS keys
- [ ] Enable `ebs_encrypted = true`
- [ ] Test encrypted distribution

### Phase 3: Dynamic Configuration (For 10+ Accounts)
- [ ] Create `accounts.yaml` schema
- [ ] Refactor locals to read from YAML
- [ ] Dynamic distribution blocks per account/region
- [ ] Per-account retention/CIS overrides

### Phase 4: Observability
- [ ] Central EventBridge bus
- [ ] Cross-account EventBridge rules
- [ ] CloudWatch dashboard
- [ ] Build failure alerting

### Phase 5: Operations
- [ ] Drift detection Lambda
- [ ] Automated rollback
- [ ] Cost allocation tags
- [ ] Runbook documentation

---

## 7. Cost Estimation (3 Accounts)

| Component | Monthly Cost (Est.) |
|-----------|---------------------|
| AMI Storage (3 accts × 5 OS × 3 retained × ~5GB) | ~$35 |
| Snapshot Copy (cross-account) | ~$12 |
| KMS Keys (if encrypted) | ~$3 |
| Image Builder Build (5 OS × monthly) | ~$200 |
| CloudWatch/EventBridge | ~$15 |
| **Total Estimated** | **~$265/mo** |

---

## 8. Security Checklist

- [x] Build instances in private subnet, no inbound access
- [x] IMDSv2 enforced
- [x] Least-privilege IAM roles
- [x] ExternalId for cross-account trust
- [x] STIG hardening (configurable level)
- [x] Component immutability via content hashing
- [ ] KMS encryption (when enabled)
- [ ] VPC endpoints for KMS/S3/SSM
- [ ] CloudTrail logging in all accounts

---

## 9. File Structure

```
golden-ami-factory/
├── CLAUDE.md                          # Project instructions
├── SOLUTION.md                        # This file
├── CROSS_ACCOUNT_SHARING.md           # Cross-account guide
├── modules/
│   ├── components/
│   ├── foundation/                    # IAM, SG, SNS
│   ├── golden_image/                  # Image Builder pipelines
│   └── recipe_registry/               # YAML-based recipes
└── environments/
    └── prod/                          # Production config
        ├── variables.tf               # target_account_ids here
        ├── locals.tf
        └── main.tf
```

---

## 10. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-11-06 | Disable EBS encryption by default | Simplifies cross-account sharing; AWS managed keys don't support cross-account |
| 2025-11-06 | Use `aws_security_group_rule` for egress | Avoids perpetual drift with `aws_vpc_security_group_egress_rule` |
| 2025-11-06 | Static `target_account_ids` list | Simple, works for 2-5 accounts; migrate to YAML when needed |
| 2025-11-06 | Single region (ap-southeast-2) | Current requirement; multi-region planned |
| 2025-11-06 | STIG default: high | Enterprise compliance baseline |

---

## 11. Next Steps

1. **Monitor** - Verify pipeline runs and cross-account sharing
2. **Validate** - Check SSM parameters in all 3 accounts
3. **Document** - Update runbooks for operations team
4. **Plan** - Evaluate encryption requirements for compliance
5. **Scale** - When adding >5 accounts, implement `accounts.yaml`

---

*Document Version: 2.1*  
*Author: Platform Engineering*  
*Last Updated: 2025-11-09*  
*Classification: Internal - Platform Team*