# AMI Sharing Environment - DEPRECATED

## ⚠️ This Environment Is No Longer Needed

**AMI sharing is now handled natively by AWS Image Builder's distribution configuration.** No separate Terraform apply is required.

### How It Works Now

The `golden_image` module's `aws_imagebuilder_distribution_configuration` resource (in `modules/golden_image/main.tf`) automatically:

1. **Shares AMIs** with target accounts specified in `var.target_account_ids`
2. **Creates SSM parameters** in each target account with the AMI ID (using `data_type = "aws:ec2:image"`)

This happens automatically when the Image Builder pipeline runs - no separate Terraform configuration or apply needed.

### Configuration

Set the target accounts in `environments/prod/variables.tf`:

```hcl
variable "target_account_ids" {
  description = "Distribution accounts to share AMIs with. Image Builder will automatically share AMIs and create SSM parameters in these accounts."
  type        = list(string)
  default     = ["774133226694", "373160674113"]
}
```

### Adding More Accounts

To add more accounts in the future, simply add them to the `target_account_ids` list in `environments/prod/variables.tf` and run `terraform apply` in the `prod` environment once. The next pipeline execution will automatically share with the new accounts.

### Why This Is Better

| Old Approach (ami_sharing) | New Approach (Native Image Builder) |
|---------------------------|-------------------------------------|
| Requires separate `terraform apply` | Single `terraform apply` in prod |
| Reads AMI IDs from SSM after build | Shares AMI during build |
| Separate state file | Single state file |
| Potential drift between build and share | Atomic operation - share happens with build |
| Manual step required | Fully automated in pipeline |

### Migration

If you have previously run the ami_sharing environment:
1. The AMIs are already shared (no action needed)
2. Future builds will use the new native approach
3. You can safely remove the ami_sharing environment from your CI/CD pipeline