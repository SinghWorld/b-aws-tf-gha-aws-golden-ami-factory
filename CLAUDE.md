# AWS Golden AMI Factory - CLAUDE.md

## Project Overview

This is a Terraform-based solution for building hardened, compliant Golden AMIs using EC2 Image Builder, with optional cross-account sharing capabilities. The project supports RHEL 8/9/10 and Windows Server 2022/2025 with STIG compliance, CloudWatch Agent, SSM Agent, and native Image Builder cross-account distribution.

## Repository Structure

```
b-aws-tf-gha-aws-golden-ami-factory/
├── challenge.txt                      # Multi-account distribution challenges reference
├── CROSS_ACCOUNT_SHARING.md           # Cross-account sharing documentation
├── README.md                          # Main documentation
├── Where-2-start.md                   # Setup guide with AWS CLI/IAM configuration
├── .github/
│   └── workflows/                     # GitHub Actions (to be created)
├── golden-ami-factory/
│   ├── .gitignore
│   ├── SOLUTION.md                    # Technical solution documentation
│   ├── modules/
│   │   ├── components/                # Custom Image Builder components
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── files/                 # YAML component definitions
│   │   │       ├── linux-hardening.yml
│   │   │       ├── linux-ssm-agent.yml
│   │   │       ├── linux-validate.yml
│   │   │       ├── windows-hardening.yml
│   │   │       ├── windows-ssm-agent.yml
│   │   │       └── windows-validate.yml
│   │   ├── foundation/                # Foundation IAM/Networking resources
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── golden_image/              # Image Builder pipelines
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── recipe_registry/           # Declarative recipe definitions (NEW)
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── recipes/               # YAML recipe definitions
│   │           ├── index.yaml
│   │           ├── rhel-8.yaml
│   │           ├── rhel-9.yaml
│   │           ├── rhel-10.yaml
│   │           ├── windows-2022.yaml
│   │           └── windows-2025.yaml
│   └── environments/
│       └── prod/                      # Production environment
│           ├── backend.hcl
│           ├── backend.hcl.example
│           ├── backend.tf
│           ├── locals.tf
│           ├── main.tf
│           ├── outputs.tf
│           ├── providers.tf
│           ├── terraform.tfvars
│           ├── variables.tf
│           └── versions.tf
```

## Key Modules

### 1. Foundation Module (`modules/foundation`)
Creates IAM roles and networking for Image Builder:
- **Build Instance Role** (`aws_iam_role.build`): EC2 role with SSM, Image Builder, and S3 log write permissions
- **Build Instance Profile** (`aws_iam_instance_profile.build`)
- **Security Group** (`aws_security_group.build`): No ingress, HTTP/HTTPS egress only
- **SNS Topic** (`aws_sns_topic.builds`): Build notifications with email subscriptions
- **Lifecycle Role** (`aws_iam_role.lifecycle`): For Image Builder lifecycle policies (AMI cleanup)
- **Image Builder Execution Role** (`aws_iam_role.imagebuilder_execution`): For distribution, SSM parameter writes, cross-account AMI sharing
  - **Dynamic cross-account permissions**: Automatically generates `sts:AssumeRole` permissions based on `var.target_account_ids` (no hardcoded account IDs)

### 2. Components Module (`modules/components`)
Creates custom Image Builder components (6 total):
| Component | Platform | Purpose |
|-----------|----------|---------|
| `windows-ssm-agent` | Windows | Checks SSM Agent version |
| `windows-hardening` | Windows | Extra hardening post-STIG |
| `windows-validate` | Windows | Baseline validation tests |
| `linux-ssm-agent` | Linux | Installs/upgrades SSM Agent on RHEL |
| `linux-hardening` | Linux | Extra hardening post-STIG |
| `linux-validate` | Linux | Baseline validation tests |

Components use content-hashed names for immutable versioning with `create_before_destroy`.
CloudWatch Agent installation uses AWS-managed Image Builder components and does not apply agent configuration.

### 3. Recipe Registry Module (`modules/recipe_registry`) - NEW
Declarative, YAML-based recipe definitions for flexible pipeline configuration:
- **Recipe definitions** in `modules/recipe_registry/recipes/*.yaml`
- **Recipe index** in `modules/recipe_registry/recipes/index.yaml`
- **Template interpolation** for AWS-managed and custom component ARNs
- **Per-recipe configuration**: STIG level, volume size, component chain, tags, lifecycle retention
- **Easy extensibility**: Add new recipes by creating YAML file + adding to index

### 4. Golden Image Module (`modules/golden_image`)
Creates complete Image Builder pipeline per recipe:
- **Image Recipe** (`aws_imagebuilder_image_recipe`): Parent image + component chain + block device mapping (EBS encryption optional)
- **Infrastructure Configuration** (`aws_imagebuilder_infrastructure_configuration`): Instance types, subnet, SG, key pair, logging
- **Distribution Configuration** (`aws_imagebuilder_distribution_configuration`): AMI naming, **cross-account sharing via `target_account_ids`**, SSM parameters in source AND target accounts
- **Image Pipeline** (`aws_imagebuilder_image_pipeline`): Links recipe + infra + distribution + execution role; optional schedule
- **Lifecycle Policy** (`aws_imagebuilder_lifecycle_policy`): Retains N newest AMIs (default 3, configurable per recipe)

## Environment Configuration (prod)

### Key Variables (`variables.tf`)
- `deployments` - Map of target accounts/regions (default: Development account 732533289325 in us-east-1)
- `deployment_name` - Selects which deployment target
- `vpc_id`, `subnet_id` - Network (required)
- `key_pair_name` - EC2 key pair (default: MYLABKEY)
- `log_bucket_name` - S3 bucket for logs (default: jcp-infra-nonprod)
- `ebs_encrypted` - Enable EBS/AMI encryption (default: false)
- `ebs_kms_key_alias` - KMS key alias if encrypted (default: alias/aws/ebs)
- `stig_level` - STIG severity: low/medium/high (default: medium)
- `target_account_ids` - Accounts for cross-account AMI sharing (default: ["774133226694", "373160674113"])
- `enabled_recipes` - Which recipes to build from registry (NEW - replaces `enabled_os`)
- `pipeline_schedule_expression` - Cron for scheduled builds (default: null = GitHub Actions)
- `images_to_retain` - AMIs to retain per OS (default: 3, can be overridden per recipe)

### Recipe Registry (NEW)
Recipes are defined in `modules/recipe_registry/recipes/`:
| Recipe Key | OS | Description |
|------------|-----|-------------|
| `rhel-8` | RHEL 8 | Linux with STIG compliance |
| `rhel-9` | RHEL 9 | Linux with STIG compliance |
| `rhel-10` | RHEL 10 | Linux with STIG compliance |
| `windows-2022` | Windows Server 2022 | Windows with STIG compliance |
| `windows-2025` | Windows Server 2025 | Windows with STIG compliance |

**To enable recipes:** Set `enabled_recipes = ["rhel-9", "windows-2025"]` in `terraform.tfvars`

### Component Chain Order (Per Recipe)

**Linux (rhel-8, rhel-9, rhel-10):**
1. `update-linux` - OS patches
2. `aws-cli-version-2-linux` - AWS CLI v2
3. `linux-ssm-agent` - SSM Agent (custom)
4. `stig-build-linux` - STIG hardening (receives `stig_level` parameter)
5. `linux-hardening` - Extra hardening (custom)
6. `linux-validate` - Validation tests (custom)
7. `amazon-cloudwatch-agent-linux` - AWS-managed CloudWatch Agent installation only
8. `simple-boot-test-linux` - Boot verification

**Windows (windows-2022, windows-2025):**
1. `update-windows` - OS patches
2. `aws-cli-version-2-windows` - AWS CLI v2
3. `windows-ssm-agent` - SSM Agent (custom)
4. `stig-build-windows` - STIG hardening (receives `stig_level` parameter)
5. `windows-hardening` - Extra hardening (custom)
6. `windows-validate` - Validation tests (custom)
7. `amazon-cloudwatch-agent-windows` - AWS-managed CloudWatch Agent installation only
8. `simple-boot-test-windows` - Boot verification

## Cross-Account AMI Sharing (Native)

**No separate ami_sharing environment needed.** Sharing is configured in `modules/golden_image/main.tf` distribution configuration:

```hcl
distribution {
  region = data.aws_region.current.region

  ami_distribution_configuration {
    target_account_ids = var.target_account_ids  # Native Image Builder sharing
  }
  
  # SSM parameter in build account
  ssm_parameter_configuration {
    parameter_name = var.ssm_parameter_name
    data_type      = "aws:ec2:image"
  }
  
  # SSM parameter in EACH distribution account
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

When pipeline runs:
1. AMI built in source account (732533289325)
2. AMI shared with all `target_account_ids`
3. SSM parameter `/golden-ami/{recipe_key}/latest` created in source + each target account
4. Lifecycle policy manages retention in source account

**To add accounts:** Update `target_account_ids` in `environments/prod/variables.tf` or `terraform.tfvars` → `terraform apply` → next pipeline run shares automatically.

**Target Account Prerequisites:** Each target account must have role `EC2ImageBuilderDistributionCrossAccountRole` with trust policy allowing source account and `ExternalId = "imagebuilder-distribution"`.

## Deployment Workflow

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

# 4. Deploy golden image pipelines (via recipe registry)
terraform plan
terraform apply
```

## GitHub Actions Integration

Workflow file: `.github/workflows/build-golden-ami.yml` (to be created)
- Runs monthly on 1st at 03:00 UTC
- Manual trigger via `workflow_dispatch`
- Deploys to prod environment
- Triggers Image Builder pipelines

Required GitHub Secrets:
- `AWS_ROLE_ARN` - IAM Role ARN for deployment
- `AWS_REGION` - e.g., `us-east-1`

## Key Technical Details

### EBS Encryption (Optional)
- Controlled by `var.ebs_encrypted` (bool, default: false)
- When true: requires `ebs_kms_key_alias` pointing to customer-managed KMS key
- KMS key must allow `imagebuilder.amazonaws.com` service
- Cross-account encrypted AMIs require target account KMS access

### Image Recipe Immutability
Recipes use content hash in name: `substr(sha1(jsonencode([parent_image_arn, component_arns, stig_level, root_volume_size, ebs_encrypted, kms_key_arn])), 0, 8)` - any change creates new recipe.

### AWS Account Architecture
| Account | ID | Purpose |
|---------|-----|---------|
| Management | 373160674113 | Source identity, IAM user "Terraform" |
| Development | 732533289325 | Golden AMI Factory, TerraformDeploymentRole |
| Production | 774133226694 | Future AMI consumption (target account) |

### Authentication Flow
1. Terraform uses AWS CLI `development` profile
2. `development` profile assumes `TerraformDeploymentRole` in Development account
3. Source credentials in `default` profile (Management account)

## Prerequisites
- Terraform >= 1.5.0
- AWS CLI with `development` profile configured
- Existing VPC with private subnet + NAT Gateway/VPC endpoints
- S3 bucket for Image Builder logs
- EC2 Key Pair in build region
- IAM permissions: EC2, Image Builder, IAM, KMS, S3, SNS, SSM

## Verification Commands

```bash
# Check SSM parameter (in any account)
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1

# Check shared AMIs (in target account)
aws ec2 describe-images --owners 732533289325 --filters "Name=name,Values=jq-golden-ami-*"

# Trigger pipeline manually
aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <arn>

# Check pipeline status
aws imagebuilder get-image --image-build-version-arn <arn> --query 'image.state'
```

## Common Issues & Troubleshooting

1. **Build Failures**: Check CloudWatch Logs `/aws/imagebuilder/<pipeline-name>` or S3 logs bucket
2. **AMI Not Shared**: Verify `target_account_ids` are valid 12-digit IDs; check launch permissions
3. **KMS Errors**: Ensure customer-managed key allows `imagebuilder.amazonaws.com`; target accounts need KMS access for encrypted AMIs
4. **AWS CLI Profile Issues**: Ensure `development` profile uses `source_profile = default` (not `management`)

## Security Considerations
- Default: No encryption (easy cross-account sharing)
- With encryption: Requires customer-managed KMS key with cross-account permissions
- Build instances in private subnet, no inbound access
- Least-privilege IAM roles for Image Builder, build instances, lifecycle
- Configurable STIG compliance level (Low/Medium/High)
- Dynamic cross-account permissions (no hardcoded account IDs in IAM policies)

## Cleanup
```bash
cd golden-ami-factory/environments/prod
terraform destroy
```

## File: `Where-2-start.md` - Key Reference
Contains complete setup guide for:
- AWS CLI installation on Windows
- IAM role creation (TerraformDeploymentRole in Development)
- Cross-account trust policies
- AWS CLI profile configuration (management → development AssumeRole)
- Testing authentication

## File: `challenge.txt` - Multi-Account Challenges
Documents known challenges beyond KMS:
1. Lifecycle policy permissions (target accounts need own policies)
2. AMI sharing limits (50 accounts/AMI default)
3. SSM parameter replication (needs target account IAM trust)
4. SNS notifications (source account only)
5. Tag propagation (target accounts may want different tags)
6. Region constraints (single region by default)
7. Drift detection (no automated verification)

---
*Generated from codebase analysis - AWS Golden AMI Factory project*