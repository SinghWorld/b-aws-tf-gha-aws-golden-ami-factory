# Multi-Account Golden AMI Factory - Enterprise Solution Design

## Executive Summary

This document outlines the challenges and architectural solutions for distributing golden AMIs from **1 source account** to **12 target accounts** (with extensibility for future accounts) using the existing Terraform-based Image Builder factory.

**Current State**: Single-account deployment using AWS managed KMS key (`alias/aws/ebs`)
**Target State**: 13-account distribution (1 source + 12 targets) with enterprise-grade security, operations, and extensibility

---

## 1. Core Challenges Analysis

### 1.1 KMS Encryption & Cross-Account Snapshot Sharing

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **AWS managed keys (`alias/aws/ebs`) are account-scoped** | Target accounts cannot decrypt snapshots encrypted with source account's key | Distribution fails silently or produces unusable AMIs |
| **No cross-account key policy on AWS managed keys** | Cannot grant `kms:Decrypt` to target accounts | Hard blocker for multi-account |
| **Image Builder re-encryption behavior** | During distribution, Image Builder *can* re-encrypt with target's key IF source key allows it | Requires customer managed key with proper policy |
| **Key rotation & lifecycle** | Rotating keys breaks existing AMI decrypt capability | Need key rotation strategy with alias stability |

**Solution Required**: Customer managed KMS key in source account with cross-account policy + target account keys for re-encryption

---

### 1.2 IAM & Cross-Account Permissions

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **Image Builder service role needs cross-account permissions** | Must create snapshots/AMIs in target accounts | Current role only has source account permissions |
| **Target accounts need to allow source account to distribute** | Each target needs resource-based policy or IAM role trust | No target-side configuration exists |
| **Lifecycle policy execution role** | Must delete AMIs/snapshots in target accounts | Current role only manages source account resources |
| **SSM Parameter replication** | Parameters must be written in each target account | Current config only writes to source account |

**Solution Required**: Cross-account IAM roles with least-privilege policies in each target account

---

### 1.3 AMI Distribution Configuration

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **`target_account_ids` variable is static list** | Adding accounts requires Terraform apply in source | Not dynamic; no GitOps-friendly onboarding |
| **Distribution config doesn't specify target regions** | All targets get AMI in source region only | May need multi-region per account |
| **AMI naming collisions** | Same AMI name in multiple accounts = confusion | Need account/region suffix in naming |
| **Launch permissions** | Distributed AMIs need explicit launch permissions | Not configured |

**Solution Required**: Dynamic target account configuration with per-account region mapping

---

### 1.4 SSM Parameter Store Replication

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **Parameters only created in source account** | Target accounts have no `/golden-ami/*/latest` parameter | Consumers in target accounts can't discover AMIs |
| **Parameter tier/encryption** | May need advanced tier for high throughput | Not configured |
| **Parameter policies (TTL)** | Auto-expiry of stale AMI references | Not implemented |

**Solution Required**: Replicate SSM parameters to each target account during distribution

---

### 1.5 Lifecycle Management Across Accounts

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **Lifecycle policy only runs in source account** | Old AMIs accumulate in target accounts (cost, quota) | No cleanup in targets |
| **`images_to_retain` applies globally** | Different retention needs per account/environment | Single value for all |
| **Orphaned snapshots** | Deleting AMI doesn't always delete snapshots | Snapshot cleanup not guaranteed |

**Solution Required**: Per-account lifecycle policies or centralized cleanup automation

---

### 1.6 Networking & Connectivity

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **Build instances need internet/VPC endpoints** | SSM, S3, package repos (yum/dnf/apt/Windows Update) | Assumes single VPC in source account |
| **Target accounts may have different VPC topologies** | Subnet/security group configs differ | Single `subnet_id` / `security_group_id` variable |
| **VPC endpoints for KMS/S3/SSM in targets** | Required for secure distribution without IGW | Not addressed |

**Solution Required**: Per-account network configuration or shared transit gateway model

---

### 1.7 Monitoring, Alerting & Observability

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **SNS topic only in source account** | Target account teams don't get build notifications | No cross-account SNS subscriptions |
| **CloudWatch metrics/logs scattered** | No centralized dashboard across 13 accounts | Single-account logging |
| **Build failure detection** | Silent failures in target distribution | No alerting on partial distribution failure |
| **AMI compliance drift** | No automated validation of distributed AMIs | Only build-time validation |

**Solution Required**: Cross-account observability stack (EventBridge → central account)

---

### 1.8 Security & Compliance

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **STIG level uniform across all accounts** | Some accounts may need different hardening | Single `stig_level` variable |
| **Component version pinning** | `x.x.x` = latest, causes drift between builds | No version lock for audit |
| **AMI compliance validation post-distribution** | No verification that target AMIs match source | Trust-but-verify gap |
| **Encryption at rest enforcement** | All accounts must enforce EBS encryption | Not validated |

**Solution Required**: Per-account compliance profiles + post-distribution validation

---

### 1.9 Cost Management & Chargeback

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **AMI storage costs in 13 accounts** | Snapshots + AMIs = significant monthly spend | No cost tracking/allocation |
| **Data transfer costs** | Cross-account snapshot copy incurs charges | Not monitored |
| **Build instance costs** | Source account bears all build costs | No chargeback to consumers |

**Solution Required**: Cost allocation tags + CUR integration + per-account budgets

---

### 1.10 Operational Excellence

| Challenge | Impact | Current Gap |
|-----------|--------|-------------|
| **Manual account onboarding** | Adding account = Terraform changes + target config | Not self-service |
| **Drift detection** | No automated check that target AMIs match source | Manual verification |
| **Rollback capability** | Bad AMI distributed to 12 accounts = 12 rollbacks | No automated rollback |
| **Runbook documentation** | Operations team needs clear procedures | Not documented |

**Solution Required**: GitOps onboarding + automated drift detection + rollback automation

---

## 2. Enterprise Architecture Design

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SOURCE ACCOUNT (Build Account)                      │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────┐  │
│  │  Terraform State │    │  Image Builder   │    │  Customer KMS Key    │  │
│  │  (S3 + DynamoDB) │───▶│  Pipelines       │───▶│  (Cross-Account)     │  │
│  └──────────────────┘    └────────┬─────────┘    └──────────┬───────────┘  │
│                                    │                       │              │
│                                    ▼                       ▼              │
│                         ┌──────────────────┐    ┌──────────────────────┐  │
│                         │  Distribution    │    │  SNS / EventBridge   │  │
│                         │  Configuration   │───▶│  (Central Bus)       │  │
│                         └────────┬─────────┘    └──────────────────────┘  │
└─────────────────────────────────┼──────────────────────────────────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  TARGET ACCT 1  │    │  TARGET ACCT 2  │    │  TARGET ACCT N  │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ IAM Role  │  │    │  │ IAM Role  │  │    │  │ IAM Role  │  │
│  │ (Trust)   │  │    │  │ (Trust)   │  │    │  │ (Trust)   │  │
│  └─────┬─────┘  │    │  └─────┬─────┘  │    │  └─────┬─────┘  │
│        │        │    │        │        │    │        │        │
│  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │
│  │ KMS Key   │  │    │  │ KMS Key   │  │    │  │ KMS Key   │  │
│  │ (Target)  │  │    │  │ (Target)  │  │    │  │ (Target)  │  │
│  └─────┬─────┘  │    │  └─────┬─────┘  │    │  └─────┬─────┘  │
│        │        │    │        │        │    │        │        │
│  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │    │  ┌─────┴─────┐  │
│  │ SSM Param │  │    │  │ SSM Param │  │    │  │ SSM Param │  │
│  │ (Latest)  │  │    │  │ (Latest)  │  │    │  │ (Latest)  │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

### 2.2 Account Onboarding Model (GitOps)

**Goal**: Add new account by editing **one file** + **one target account Terraform apply**

#### Source Account: `accounts.yaml` (Single Source of Truth)

```yaml
# accounts.yaml - Managed in source account repo
accounts:
  - account_id: "111111111111"
    account_name: "prod-workloads"
    account_alias: "prod-wl"
    regions:
      - us-east-1
      - us-west-2
    ami_distribution:
      enabled: true
      retention_count: 6
      stig_level: "high"
    networking:
      vpc_id: "vpc-xxxxxxxx"
      subnet_ids: ["subnet-aaa", "subnet-bbb"]
      security_group_id: "sg-xxxxx"
    notifications:
      sns_topic_arn: "arn:aws:sns:us-east-1:111111111111:ami-build-alerts"
    tags:
      CostCenter: "12345"
      Environment: "Production"
      Owner: "platform-team"

  - account_id: "222222222222"
    account_name: "staging"
    account_alias: "staging"
    regions:
      - us-east-1
    ami_distribution:
      enabled: true
      retention_count: 3
      stig_level: "medium"
    # ... etc
```

#### Target Account: Minimal Bootstrap Stack

Each target account deploys a **bootstrap stack** (CloudFormation/Terraform) once:

```hcl
# target-account-bootstrap/main.tf (deploy once per target account)
resource "aws_iam_role" "imagebuilder_distribution" {
  name = "golden-ami-distribution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::SOURCE_ACCOUNT:root" }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "golden-ami-factory-distribution"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "distribution_perms" {
  role = aws_iam_role.imagebuilder_distribution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateImage",
        "ec2:CopyImage",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:DeregisterImage",
        "ec2:DescribeImages",
        "ec2:DescribeSnapshots",
        "ec2:ModifyImageAttribute",
        "ec2:ModifySnapshotAttribute",
        "ec2:ResetImageAttribute",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "ssm:PutParameter",
        "ssm:DeleteParameter",
        "ssm:GetParameter"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_kms_key" "target_ebs" {
  description = "EBS encryption key for golden AMI distribution"
  deletion_window_in_days = 30
  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "AllowRoot", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = "kms:*", Resource = "*" },
      { Sid = "AllowSourceAccount", Effect = "Allow", Principal = { AWS = "arn:aws:iam::SOURCE_ACCOUNT:root" }, Action = ["kms:Decrypt","kms:DescribeKey","kms:ReEncrypt*","kms:GenerateDataKey*"], Resource = "*" },
      { Sid = "AllowImageBuilder", Effect = "Allow", Principal = { Service = "imagebuilder.amazonaws.com" }, Action = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"], Resource = "*" }
    ]
  })
}

resource "aws_kms_alias" "target_ebs" {
  name          = "alias/golden-ami-target-ebs"
  target_key_id = aws_kms_key.target_ebs.key_id
}
```

---

### 2.3 KMS Key Strategy

#### Source Account: Customer Managed Key (Shared)

```hcl
# Source account - single key shared to all targets
resource "aws_kms_key" "source_golden_ami" {
  description = "Golden AMI factory - source account encryption key"
  deletion_window_in_days = 30
  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "AllowRoot", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = "kms:*", Resource = "*" },
      { Sid = "AllowImageBuilder", Effect = "Allow", Principal = { Service = "imagebuilder.amazonaws.com" }, Action = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"], Resource = "*" },
      { Sid = "AllowTargetAccounts", Effect = "Allow", Principal = { AWS = ["arn:aws:iam::111111111111:root", "arn:aws:iam::222222222222:root", ...] }, Action = ["kms:Decrypt","kms:DescribeKey","kms:ReEncrypt*","kms:GenerateDataKey*"], Resource = "*" }
    ]
  })
}

resource "aws_kms_alias" "source_golden_ami" {
  name          = "alias/golden-ami-source-ebs"
  target_key_id = aws_kms_key.source_golden_ami.key_id
}
```

#### Distribution Behavior

| Scenario | What Happens |
|----------|--------------|
| Source builds AMI | Encrypted with `alias/golden-ami-source-ebs` |
| Distribution to Target A | Image Builder re-encrypts snapshot with Target A's `alias/golden-ami-target-ebs` |
| Target A launches instance | Uses Target A's key - no cross-account dependency |
| Source key rotated | Existing AMIs still decryptable (key material retained); new AMIs use new key version |

---

### 2.4 Dynamic Target Configuration

#### Replace Static Variables with Data-Driven Approach

```hcl
# locals.tf - Replace hardcoded target_account_ids
locals {
  # Load from accounts.yaml (using yamldecode or external data source)
  target_accounts = yamldecode(file("${path.module}/accounts.yaml"))["accounts"]
  
  # Filter enabled accounts
  enabled_targets = { for a in local.target_accounts : a.account_id => a if a.ami_distribution.enabled }
  
  # Flatten for Image Builder distribution config
  distribution_accounts = [for a in local.enabled_targets : a.account_id]
  
  # Per-account region mapping (for multi-region distribution)
  account_regions = { for a in local.enabled_targets : a.account_id => a.regions }
}
```

#### Distribution Configuration Per Account/Region

```hcl
# In golden_image module - dynamic distribution blocks
dynamic "distribution" {
  for_each = var.target_account_configs
  content {
    region = distribution.value.region
    
    ami_distribution_configuration {
      name        = "${local.ami_name}-${distribution.value.account_alias}-${distribution.value.region}"
      kms_key_id  = distribution.value.target_kms_key_arn
      ami_tags = merge(var.tags, {
        TargetAccount = distribution.value.account_id
        TargetRegion  = distribution.value.region
      })
    }
    
    ssm_parameter_configuration {
      parameter_name = "${var.ssm_parameter_prefix}/${var.os_key}/latest"
      data_type      = "aws:ec2:image"
      ami_account_id = distribution.value.account_id
    }
  }
}
```

---

### 2.5 Lifecycle Policy - Per Account

```hcl
# Each target account gets its own lifecycle policy
resource "aws_imagebuilder_lifecycle_policy" "target" {
  for_each = var.target_account_configs
  
  name        = "${local.base_name}-${each.value.account_alias}"
  description = "Retain ${each.value.retention_count} ${var.display_name} images in ${each.value.account_name}"
  execution_role = each.value.lifecycle_role_arn
  resource_type  = "AMI_IMAGE"
  
  policy_detail {
    action {
      type = "DELETE"
      include_resources { amis = true, snapshots = true }
    }
    filter { type = "COUNT", value = each.value.retention_count }
  }
  
  resource_selection {
    tag_map = { GoldenImage = "${var.os_key}-${each.value.account_alias}" }
  }
}
```

---

## 3. Implementation Roadmap

### Phase 1: Foundation (Week 1-2) - **Do First**
- [ ] Create customer managed KMS key in source account with cross-account policy
- [ ] Update `ebs_kms_key_alias` variable default to new key alias
- [ ] Create target account bootstrap stack (IAM role + KMS key)
- [ ] Deploy bootstrap to all 12 target accounts
- [ ] Test single-account distribution to one target

### Phase 2: Dynamic Configuration (Week 2-3)
- [ ] Create `accounts.yaml` with all 12 accounts
- [ ] Refactor locals to read from `accounts.yaml`
- [ ] Make distribution configuration dynamic per account/region
- [ ] Add per-account retention/stig_level/networking overrides
- [ ] Test full 12-account distribution

### Phase 3: Observability (Week 3-4)
- [ ] Central EventBridge bus in source account
- [ ] Cross-account EventBridge rules in each target → central bus
- [ ] Central CloudWatch dashboard for all accounts
- [ ] SNS/ChatOps notifications for build success/failure per account
- [ ] AMI compliance validation Lambda (post-distribution)

### Phase 4: Operations & Governance (Week 4-5)
- [ ] Drift detection: Lambda compares source vs target AMI attributes
- [ ] Automated rollback: SSM Automation document for mass deregistration
- [ ] Cost allocation tags + CUR dashboard
- [ ] Runbook documentation (Confluence/GitBook)
- [ ] Terraform module for target account bootstrap (versioned)

### Phase 5: Self-Service Onboarding (Week 5-6)
- [ ] Service Catalog product for target account bootstrap
- [ ] GitHub Actions workflow: "Onboard New Target Account"
- [ ] Automated validation pipeline for new accounts
- [ ] Account deprovisioning procedure

---

## 4. Extensibility Design - Adding New Accounts

### 4.1 New Account Onboarding Checklist (5 minutes)

```bash
# 1. Add entry to accounts.yaml in source repo
# 2. Commit & push → triggers validation pipeline
# 3. In target account: deploy bootstrap stack (one-click via Service Catalog)
# 4. Pipeline auto-detects new account on next run
```

### 4.2 accounts.yaml Schema (Extensible)

```yaml
accounts:
  - account_id: "999999999999"          # Required
    account_name: "new-workload"         # Required
    account_alias: "new-wl"              # Required (short, unique, DNS-safe)
    regions:                              # Required
      - us-east-1
      - eu-west-1
    ami_distribution:
      enabled: true                       # Default: true
      retention_count: 3                  # Default: 3
      stig_level: "medium"                # Default: medium
    networking:                           # Optional - uses defaults if omitted
      vpc_id: "vpc-xxx"
      subnet_ids: ["subnet-xxx"]
      security_group_id: "sg-xxx"
    notifications:                        # Optional
      sns_topic_arn: "arn:aws:sns:..."
    tags:                                 # Merged with global tags
      CostCenter: "99999"
      Team: "platform"
```

### 4.3 Feature Flags for Gradual Rollout

```yaml
# In accounts.yaml per account
features:
  distribution_enabled: true
  lifecycle_policy_enabled: true
  compliance_validation_enabled: true
  cross_region_copy_enabled: false
  custom_components_enabled: false
```

---

## 5. Risk Mitigation & Rollback

### 5.1 Distribution Failure Scenarios

| Failure Mode | Detection | Mitigation |
|--------------|-----------|------------|
| KMS access denied | CloudTrail + EventBridge alert | Pre-flight IAM policy validator |
| Target account quota exceeded | CloudWatch metric `EC2 > AMIs > Limit` | Quota monitoring + auto-request |
| Snapshot copy timeout | Image Builder pipeline status | Increased timeout + retry logic |
| AMI name collision | Pre-check via `describe-images` | Account/region suffix in naming |

### 5.2 Rollback Procedure

```bash
# Emergency rollback - single command per account
aws ssm start-automation-execution \
  --document-name "GoldenAMIRollback" \
  --parameters "AccountId=111111111111,AmiNamePattern=jq-golden-ami-rhel9-*"
```

---

## 6. Cost Estimation (13 Accounts)

| Component | Monthly Cost (Est.) | Notes |
|-----------|---------------------|-------|
| AMI Storage (13 accts × 5 OS × 3 retained × ~5GB) | ~$150 | Snapshots ~$0.05/GB-mo |
| Snapshot Copy (cross-account) | ~$50 | $0.02/GB per copy |
| KMS Keys (13 customer keys) | ~$13 | $1/key/mo |
| Image Builder Build (5 OS × monthly) | ~$200 | Build instances + licensing |
| CloudWatch/EventBridge | ~$50 | Logs + metrics + events |
| **Total Estimated** | **~$463/mo** | Excludes data transfer |

---

## 7. Security Checklist

- [ ] KMS keys use customer managed keys (not AWS managed)
- [ ] Key policies follow least privilege
- [ ] Cross-account roles use ExternalId
- [ ] Image Builder service role scoped to specific actions
- [ ] AMIs encrypted at rest in all accounts
- [ ] SSM parameters encrypted (SecureString)
- [ ] VPC endpoints for KMS/S3/SSM in all accounts
- [ ] Build instances use IMDSv2
- [ ] STIG components validated post-distribution
- [ ] Audit logging via CloudTrail in all accounts

---

## 8. Appendix: File Structure Changes

```
golden-ami-factory/
├── accounts.yaml                 # NEW - Single source of truth for all accounts
├── environments/
│   └── prod/
│       ├── main.tf               # Modified - dynamic target configuration
│       ├── locals.tf             # Modified - reads accounts.yaml
│       ├── variables.tf          # Modified - remove static target_account_ids
│       └── versions.tf
├── modules/
│   ├── foundation/
│   │   ├── main.tf               # Modified - add source KMS key
│   │   ├── outputs.tf            # Modified - export KMS key ARN
│   │   └── variables.tf
│   ├── golden_image/
│   │   ├── main.tf               # Modified - dynamic distribution blocks
│   │   ├── variables.tf          # Modified - target account config object
│   │   └── outputs.tf
│   └── target_bootstrap/         # NEW - Deploy once per target account
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── SOLUTION.md                   # THIS FILE
```

---

## 9. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-01-XX | Customer managed KMS key (single source, per-target) | AWS managed keys don't support cross-account; per-target keys enable re-encryption |
| 2025-01-XX | accounts.yaml as single source of truth | GitOps-friendly, version-controlled, reviewable |
| 2025-01-XX | Target bootstrap stack (IAM + KMS) | Least privilege; target account controls own resources |
| 2025-01-XX | EventBridge for central observability | Native AWS, no third-party, scales to 100s of accounts |
| 2025-01-XX | Per-account lifecycle policies | Different retention needs; avoids cross-account delete complexity |

---

## 10. Next Steps

1. **Review this document** with platform/security/networking teams
2. **Approve KMS key strategy** - create source key first (irreversible after use)
3. **Deploy target bootstrap** to 1-2 pilot accounts
4. **Validate end-to-end** distribution pipeline
5. **Roll out to remaining 10 accounts** in batches
6. **Implement Phase 3-5** incrementally

---

*Document Version: 1.0*  
*Author: Platform Engineering*  
*Review Cycle: Quarterly or on major architecture change*