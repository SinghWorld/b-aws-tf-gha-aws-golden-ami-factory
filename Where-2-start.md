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

3. Cross-Account AMI Sharing - Native Image Builder (NEW)

**The separate ami_sharing environment is deprecated.** AMI sharing is now handled natively by AWS Image Builder's distribution configuration during pipeline execution.

- Modified: modules/golden_image/main.tf - Distribution configuration includes target_account_ids and cross-account SSM parameters
- Modified: environments/prod/variables.tf - target_account_ids default now includes ["774133226694", "373160674113"]
- Deprecated: environments/ami_sharing/ - No longer needed (kept for reference with README)

Usage (Single Apply - No Separate ami_sharing Step):

Build Golden AMIs with cross-account sharing (no encryption, with CloudWatch Agent):
```bash
cd environments/prod
terraform apply -var="ebs_encrypted=false"
```

The `target_account_ids` variable in `environments/prod/variables.tf` (or terraform.tfvars) specifies the list of AWS account IDs to share AMIs with. Image Builder automatically:
1. Shares the AMI with all target accounts during build
2. Creates SSM parameters in each target account with the AMI ID

To add more accounts, simply update `target_account_ids` in prod and re-apply. The next pipeline run will share with new accounts automatically.

See `CROSS_ACCOUNT_SHARING.md` for detailed modular approach documentation.



Excellent. Both member accounts are accessible, and you've confirmed that OrganizationAccountAccessRole exists in each account.

For your Golden Image project, I recommend keeping the design simple and separating the human console access from the Terraform automation access.

Your intended setup will be:
- Management account (373160674113): Holds the IAM user Terraform. This is your starting identity for automation.
- Development account (732533289325): Hosts the Golden AMI Factory and a dedicated role called TerraformDeploymentRole.
- Production account (774133226694): Leave it unchanged for now. We can configure it later if you need to distribute AMIs there.
Terraform will authenticate using the management account IAM user's credentials, then assume the dedicated role in Development using AWS STS. You won't need to create another IAM user or store another set of access keys in Development.
1. Create the dedicated Terraform role in Development
First, switch your AWS Console to the Development account (732533289325).

Open IAM → Roles and follow these steps:
1. Select Create role.
2. For Trusted entity type, select Custom trust policy.
3. Replace the sample trust policy with the following:
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowManagementTerraformUser",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::373160674113:user/Terraform"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}


This trusts only the Terraform IAM user in your management account, rather than every identity in that account.
4. Select Next.
5. Attach the AdministratorAccess policy for the initial Golden AMI Factory implementation.
6. Select Next.
7. Enter the role name:
TerraformDeploymentRole


8. Create the role.
Expected role
arn:aws:iam::732533289325:role/TerraformDeploymentRole


Security note: AdministratorAccess grants broad permissions in Development. I'm using it as a temporary bootstrap permission so you can establish the workflow without running into numerous missing IAM permissions. Before production use, we should replace it with a tailored policy covering EC2 Image Builder, EC2, S3, SSM, IAM PassRole, KMS, CloudWatch Logs and the other services your implementation actually uses.

The trust policy and permission policy serve different purposes: the trust policy determines who can assume the role, while the attached permissions determine what that role can do. 
AWS Identity and Access Management+2

2. Allow the Terraform user to assume the new role
Now switch back to your Management account (373160674113) as IAM user Terraform.

Open IAM → Users, select Terraform, then:
1. Select Permissions.
2. Select Add permissions.
3. Choose Create inline policy.
4. Select the JSON tab.
5. Paste this policy:
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeDevelopmentTerraformRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::732533289325:role/TerraformDeploymentRole"
    }
  ]
}


6. Select Next.
7. Policy name:
AssumeDevelopmentTerraformRole


8. Select Create policy.

If your Terraform user already has AdministratorAccess, that policy already allows sts:AssumeRole; this additional policy is then not technically necessary. The scoped policy is useful if you later remove broad administrator permissions from the user.

This completes the two sides of cross-account access:
- Development trusts the specific management-account IAM user.
- The management-account IAM user is authorised to assume the Development role.

AWS Identity and Access Management+1
3. Install AWS CLI on your Windows laptop
Since you are using Windows, open PowerShell.

Check whether AWS CLI is already installed:
aws --version


If it isn't installed, run the official AWS installation command:
irm https://awscli.amazonaws.com/v2/install.ps1 | iex


Close and reopen PowerShell, then verify:
aws --version


This installs AWS CLI v2. 
AWS Command Line Interface

4. Create an access key for the Terraform IAM user
The AWS CLI needs an authentication method. In your current setup, we will use an access key belonging to the Terraform IAM user in the management account.

This is a long-term credential used only to obtain temporary credentials for the Development role.

In the Management account:
1. Open IAM → Users → Terraform.
2. Select Security credentials.
3. Find Access keys.
4. Select Create access key.
5. Choose Command Line Interface (CLI).
6. Acknowledge the recommendation and create the key.
7. Download the CSV or securely copy the access key ID and secret access key.
Important
 You will only be shown the secret access key at creation. Store it securely. Never share it here, commit it to Git, or put it in Terraform code.

Do not create access keys for the Development account's role or for your root user.
5. Configure your management account CLI profile
In PowerShell, run:
aws configure --profile management


Enter the following when prompted:
Prompt	Value
AWS Access Key ID	Management Terraform user's access key
AWS Secret Access Key	Management Terraform user's secret key
Default region	ap-southeast-2
Default output format	json

This creates a management profile containing your source credentials.
6. Configure the Development AssumeRole profile
Now open the AWS CLI config file:
notepad $env:USERPROFILE\.aws\config


Add the following:
[profile development]
role_arn = arn:aws:iam::732533289325:role/TerraformDeploymentRole
source_profile = management
role_session_name = balraj-golden-ami
region = ap-southeast-2
output = json


Save the file.

Your AWS CLI configuration will now work like this:
Authentication flow
Management account

IAM user: Terraform

Profile: management

AWS STS AssumeRole

Development account

Role: TerraformDeploymentRole

Profile: development


Golden AMI Factory

EC2 Image Builder, SSM, EC2, S3 and related services


The AWS CLI automatically calls STS to assume the role and obtains temporary credentials. It can refresh those credentials when required. 
AWS Command Line Interface+1

7. Test your Development account access
Run these commands in PowerShell.

Test 1 — Check configured profiles
aws configure list-profiles


Expected:
management
development


Test 2 — Check your source identity
aws sts get-caller-identity --profile management


Expected account:
373160674113


Test 3 — Check your Development role
aws sts get-caller-identity --profile development


Expected output will look similar to:
{
    "UserId": "AROAXXXXXXXXXXXXX:balraj-golden-ami",
    "Account": "732533289325",
    "Arn": "arn:aws:sts::732533289325:assumed-role/TerraformDeploymentRole/balraj-golden-ami"
}


Success condition
 The account must be 732533289325, and the ARN must contain assumed-role/TerraformDeploymentRole.

You can also test access to EC2:
aws ec2 describe-regions --profile development



8. Configure Terraform to use Development
In your Terraform provider configuration, use the Development profile:
provider "aws" {
  region  = "ap-southeast-2"
  profile = "development"

  default_tags {
    tags = {
      Environment = "Development"
      Project     = "Golden-AMI-Factory"
      ManagedBy   = "Terraform"
    }
  }
}


This means your Terraform commands will use the Development account automatically when using this provider configuration.

For now, don't configure Production. We will keep the Golden AMI build process isolated in Development.
9. Your target architecture
Account	Purpose	Access
Management 373160674113	Source identity and billing	IAM user Terraform
Development 732533289325	Golden AMI Factory	TerraformDeploymentRole
Production 774133226694	Future AMI consumption	Configure later

Official AWS documentation:
- AWS CLI — Using an IAM role
- Creating an IAM role
- Installing AWS CLI v2 on Windows
Let's complete this in stages
I recommend you complete Steps 1 and 2 first, then we can test the role before configuring your laptop.
Development role creation

Created TerraformDeploymentRole with AdministratorAccess


Not started yet

Encountered an error


Management IAM user permission

Added AssumeDevelopmentTerraformRole policy


Terraform user already has AdministratorAccess

Not started yet

Encountered an error

Continue
Once these are ready, we'll configure and test your local AWS CLI, then move on to the Terraform-based Golden AMI Factory.

















dc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$ aws sts get-caller-identity --profile development

aws: [ERROR]: The source_profile "management" referenced in the profile "development" does not exist.
dc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$ aws sts get-caller-identity --profile management

aws: [ERROR]: The config profile (management) could not be found
dc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$ aws sts get-caller-identity --profile development

aws: [ERROR]: The source_profile "management" referenced in the profile "development" does not exist.
dc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$ aws configure list-profiles
development
default
dc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$ aws sts get-caller-identity
{
    "UserId": "AIDAVNYQ4ANAYWLE2OUCD",
    "Account": "373160674113",
    "Arn": "arn:aws:iam::373160674113:user/Terraform"
}
dc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$ aws sts get-caller-identity --profile development

aws: [ERROR]: The source_profile "management" referenced in the profile "development" does not exist.
dc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$ cat ~/.aws/config 
#[default]
#region = us-east-1
# region = ap-southeast-2

[profile development]
role_arn = arn:aws:iam::732533289325:role/TerraformDeploymentRole
source_profile = management
role_session_name = balraj-golden-ami
region = us-east-1
#output = jsondc-ops@terraform:~/b-aws-tf-gha-aws-golden-ami-factory/golden-ami-factory/environments/prod$












Worked for 7s







Your output shows that your AWS credentials are working correctly. The problem is a simple AWS CLI profile configuration issue.

You already have valid management-account credentials in the default profile, but your Development profile is looking for a profile called management, which does not exist.

We can fix this without creating another access key.
1. Understand your current configuration
Your command confirms:
{
    "UserId": "AIDAVNYQ4ANAYWLE2OUCD",
    "Account": "373160674113",
    "Arn": "arn:aws:iam::373160674113:user/Terraform"
}


This confirms:
Management authentication working
Profile	Current status
default	Working
management	Does not exist
development	Configured incorrectly

Your current configuration says:
[profile development]
role_arn = arn:aws:iam::732533289325:role/TerraformDeploymentRole
source_profile = management


The issue is source_profile = management.
2. Fix your Development profile
Since your existing default profile already authenticates as the Terraform IAM user, we will reuse it.

Run these commands on your Linux machine:
aws configure set role_arn arn:aws:iam::732533289325:role/TerraformDeploymentRole --profile development

aws configure set source_profile default --profile development

aws configure set role_session_name balraj-golden-ami --profile development

aws configure set region ap-southeast-2 --profile development

aws configure set output json --profile development


This changes the Development profile to use your existing default credentials.
3. Verify your configuration
Run:
cat ~/.aws/config


Expected configuration:
[profile development]
role_arn = arn:aws:iam::732533289325:role/TerraformDeploymentRole
source_profile = default
role_session_name = balraj-golden-ami
region = ap-southeast-2
output = json


Your ~/.aws/credentials file should contain the credentials for the default profile. Do not share that file or its contents.
4. Test authentication
Run the following commands in order.

Test A — Management account
aws sts get-caller-identity


Expected account:
373160674113


Test B — Development account
aws sts get-caller-identity --profile development


Expected account:
732533289325


Expected ARN format:
arn:aws:sts::732533289325:assumed-role/TerraformDeploymentRole/balraj-golden-ami


Target result
 Your Development profile should authenticate through STS and assume TerraformDeploymentRole.
5. Test EC2 permissions
Once the STS test succeeds, run:
aws ec2 describe-regions --profile development


Then:
aws ec2 describe-images \
  --owners self \
  --region ap-southeast-2 \
  --profile development


These commands verify that the assumed role can call EC2 APIs.

6. Your final authentication architecture
Linux Terraform host

AWS CLI configuration

Default profile

Management account

373160674113
Working


Development profile

AssumeRole

732533289325
To test



Terraform Golden AMI Factory


My recommendation: Keep default as your management identity and use named profiles for each AWS member account. Later, we can add a Production profile using the same pattern.
Your next action
Run the commands in Step 2 and then execute:
aws sts get-caller-identity --profile development