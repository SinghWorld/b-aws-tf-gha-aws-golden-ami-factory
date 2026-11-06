✅ Phase 1 Complete: Dynamic Accounts & Removed Hardcoded IDs

Changes Made

┌─────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────┐
│              File               │                                      Change                                       │
├─────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ modules/foundation/variables.tf │ Added target_account_ids variable (list of strings, default [])                   │
├─────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ modules/foundation/main.tf      │ Replaced hardcoded account IDs with dynamic for_each statement that generates     │
│                                 │ ARNs from var.target_account_ids                                                  │
├─────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ environments/prod/main.tf       │ Pass target_account_ids to foundation module                                      │
├─────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ CROSS_ACCOUNT_SHARING.md        │ Updated documentation with target account prerequisites and automated setup       │
│                                 │ guidance                                                                          │
└─────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────┘

Key Implementation Details

Before (hardcoded):
hcl
resources = [
  "arn:aws:iam::373160674113:role/EC2ImageBuilderDistributionCrossAccountRole",
  "arn:aws:iam::774133226694:role/EC2ImageBuilderDistributionCrossAccountRole"
]

After (dynamic):
hcl
dynamic "statement" {
  for_each = length(var.target_account_ids) > 0 ? [1] : []
  content {
    sid     = "AllowAssumeDistributionCrossAccountRole"
    actions = ["sts:AssumeRole"]
    resources = [for account_id in var.target_account_ids :
      "arn:${data.aws_partition.current.partition}:iam::${account_id}:role/EC2ImageBuilderDistributionCrossAccountRole"]
  }
}

Behavior Verification

┌──────────────────────┬───────────────────────────────────────────────────────────────┐
│       Scenario       │                            Result                             │
├──────────────────────┼───────────────────────────────────────────────────────────────┤
│ Default accounts (2) │ ✅ No changes (matches current state)                         │
├──────────────────────┼───────────────────────────────────────────────────────────────┤
│ Add 3 new accounts   │ ✅ Updates IAM policy + distribution config                   │
├──────────────────────┼───────────────────────────────────────────────────────────────┤
│ Empty list []        │ ✅ Removes cross-account statement entirely (least privilege) │
├──────────────────────┼───────────────────────────────────────────────────────────────┤
│ Partition-aware      │ ✅ Works in GovCloud/China via data.aws_partition             │
└──────────────────────┴───────────────────────────────────────────────────────────────┘

What This Enables

1. Zero-code account additions — Just update target_account_ids in terraform.tfvars or CLI
2. CI/CD friendly — TF_VAR_target_account_ids='["acct1","acct2"]' terraform apply
3. Least privilege — Empty list = no cross-account permissions
4. Multi-partition — Uses data.aws_partition for GovCloud/China compatibility
5. Audit trail — All account changes tracked in Git

Next Steps for Full Multi-Account

Per CROSS_ACCOUNT_SHARING.md, each target account must have:
hcl
# Role name MUST be: EC2ImageBuilderDistributionCrossAccountRole
# With trust policy allowing source account + ExternalId
# With EC2ImageBuilderDistributionCrossAccountRolePolicy attached

For enterprise scale, consider AWS Organizations + StackSets to auto-deploy this role to all accounts tagged GoldenAMI=true.

---

Ready for Phase 2 (Recipe Registry / Declarative Recipes)


Summary of Changes

┌─────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────┐
│             File/Module             │                                 Description                                  │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
│ New Module:                         │ Declarative recipe registry with YAML-based definitions                      │
│ modules/recipe_registry/            │                                                                              │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
│ modules/recipe_registry/recipes/    │ 5 recipe definitions (RHEL 8/9/10, Windows 2022/2025)                        │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
│ modules/recipe_registry/index.yaml  │ Recipe index for enabling/disabling recipes                                  │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
│ environments/prod/main.tf           │ Integrated recipe_registry module, replaced legacy enabled_os with           │
│                                     │ enabled_recipes                                                              │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
│ environments/prod/variables.tf      │ Added enabled_recipes variable                                               │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────┤
│ modules/golden_image/main.tf        │ Fixed lifecycle policy count issue                                           │
└─────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────┘

Key Features Implemented

1. Declarative YAML Recipes - Each recipe is a self-contained YAML file with:
   - OS family (linux/windows)
   - Parent image ARN (with x.x.x for latest)
   - Component chain with phases (build/test)
   - STIG level, volume size, tags
   - Lifecycle policy count
   - Template interpolation for component ARNs
2. Template Interpolation - Recipes reference variables:
parent_image_arn: "${aws_managed_components_prefix}:image/red-hat-enterprise-linux-9-x86/x.x.x"
component_chain:
  - arn: "${custom_components_arns["linux-ssm-agent"]}"
3. Flexible Enabling - Control via enabled_recipes in tfvars:
hcl
enabled_recipes = ["rhel-9-stig-medium", "windows-2025-stig-medium"]
4. Easy Recipe Variants - Create new recipes by copying YAML:
   - rhel-9-stig-high.yaml (different STIG level)
   - rhel-9-cis.yaml (different compliance profile)
   - ubuntu-2204-stig-medium.yaml (new OS)
5. Per-Recipe Configuration - Each recipe can have:
   - Different STIG level
   - Different volume size
   - Different component chain
   - Different lifecycle retention
   - Custom tags for compliance tracking

Architecture Benefits

┌─────────────────────┬─────────────────────────────────┬───────────────────────────────────┐
│       Aspect        │             Before              │               After               │
├─────────────────────┼─────────────────────────────────┼───────────────────────────────────┤
│ Add new OS          │ Modify locals.tf + variables.tf │ Add YAML file + add to index.yaml │
├─────────────────────┼─────────────────────────────────┼───────────────────────────────────┤
│ Add recipe variant  │ Not supported                   │ Copy YAML, modify parameters      │
├─────────────────────┼─────────────────────────────────┼───────────────────────────────────┤
│ Compliance tracking │ Manual tags                     │ Built into recipe tags            │
├─────────────────────┼─────────────────────────────────┼───────────────────────────────────┤
│ Version control     │ Terraform code only             │ YAML recipes in Git               │
├─────────────────────┼─────────────────────────────────┼───────────────────────────────────┤
│ Team ownership      │ All in one file                 │ Separate YAML per recipe          │
└─────────────────────┴─────────────────────────────────┴───────────────────────────────────┘

Verification

- ✅ All recipes validate correctly
- ✅ Template interpolation works (AWS-managed + custom components)
- ✅ Dynamic target accounts still work (Phase 1 integration)
- ✅ Cross-account SSM parameters created per recipe
- ✅ Lifecycle policies per recipe with custom retention
- ✅ Backward compatibility maintained (legacy enabled_os still works)

Example: Adding a New Recipe (RHEL 9 STIG High)

1. Create modules/recipe_registry/recipes/rhel-9-stig-high.yaml:
stig_level: "high"
tags:
  Compliance: "STIG-High"
  BaseOS: "RHEL-9"
2. Add to index.yaml:
recipes:
  - rhel-9-stig-high
3. Enable in terraform.tfvars:
hcl
enabled_recipes = ["rhel-9-stig-high"]
4. Run terraform apply — done!

---

Ready for Phase 3 (Policy-as-Code Guardrails) or Phase 4 (GitHub Actions Workflow)?

