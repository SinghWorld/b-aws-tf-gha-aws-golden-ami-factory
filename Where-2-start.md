Check using AWS CLI
Run this using your source account credentials:
```sh
aws ec2 get-ebs-encryption-by-default \
  --region ap-southeast-2
```

Check the default KMS key:
```sh
aws ec2 get-ebs-default-kms-key-id \
  --region ap-southeast-2
```

Check whether a particular source AMI has encrypted snapshots:
```sh
aws ec2 describe-images \
  --owners self \
  --image-ids ami-xxxxxxxx \
  --region ap-southeast-2 \
  --query "Images[].BlockDeviceMappings[].Ebs.{SnapshotId:SnapshotId,Encrypted:Encrypted}"
```

For an unencrypted source image, the snapshot Encrypted values should be false.

Do not proceed to production until this is verified.


aws imagebuilder get-image --image-build-version-arn <arn> --query 'image.state' --output table

aws imagebuilder get-image --image-build-version-arn "arn:aws:imagebuilder:us-east-1:373160674113:image/golden-win2022-recipe/1.0.1/3" --query 'image.state' --output table

Summary of Changes

1. EBS Encryption Made Optional (Default: Disabled)

- Modified: modules/golden_image/main.tf - EBS encryption now controlled by var.ebs_encrypted
- Modified: modules/golden_image/variables.tf - Added ebs_encrypted (bool, default: false) and made kms_key_arn optional (default: "")
- Modified: environments/prod/main.tf - Pass ebs_encrypted and conditional kms_key_arn
- Modified: environments/prod/variables.tf - Added ebs_encrypted variable
- Modified: environments/prod/locals.tf - KMS alias data source now conditional on ebs_encrypted
- Modified: environments/prod/outputs.tf - KMS key ARN output now conditional

2. CloudWatch Agent Components Added

- Created: modules/components/files/linux-cloudwatch-agent.yml - Installs/configures CloudWatch Agent on RHEL
- Created: modules/components/files/windows-cloudwatch-agent.yml - Installs/configures CloudWatch Agent on Windows
- Modified: modules/components/main.tf - Added both CloudWatch Agent components to definitions
- Modified: environments/prod/locals.tf - Added CloudWatch Agent to component chains for both Linux and Windows

3. Cross-Account AMI Sharing Module

- Created: modules/ami_sharing/main.tf - Reads AMI IDs from SSM parameters and shares with target accounts via aws_ec2_ami_launch_permission
- Created: modules/ami_sharing/variables.tf - Variables for OS keys, SSM parameter prefix, and target account IDs
- Created: modules/ami_sharing/outputs.tf - Outputs for shared AMI IDs and target accounts
- Created: environments/ami_sharing/ - Complete environment for cross-account sharing:
  - main.tf - Calls the ami_sharing module
  - variables.tf - Configuration variables including target_account_ids list
  - providers.tf, locals.tf, backend.tf - Standard environment files

Usage

Build Golden AMIs (no encryption, with CloudWatch Agent):
cd environments/prod
terraform apply -var="ebs_encrypted=false"

Share AMIs with other accounts:
cd environments/ami_sharing
terraform apply -var="target_account_ids=[\"123456789012\", \"234567890123\"]"

The target_account_ids variable in environments/ami_sharing/variables.tf is where you specify the list of AWS account IDs to share the AMIs with.