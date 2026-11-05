# AWS Golden AMI Factory - Architecture Diagrams

## Mermaid Connectivity Diagram

```mermaid
flowchart TD
    %% External / User Layer
    GH_Actions[("GitHub Actions<br/>Monthly Schedule / Manual")]:::external
    Terraform_CLI["Terraform CLI<br/>(Development Profile)"]:::external
    User[("User / Admin")]:::external

    %% AWS Accounts
    subgraph Mgmt_Account["Management Account (373160674113)"]
        direction TB
        IAM_User["IAM User: Terraform<br/>(Source Credentials)"]:::mgmt
        Mgmt_Profile["AWS CLI Profile: default"]:::mgmt
    end

    subgraph Dev_Account["Development Account (732533289325) - BUILD ACCOUNT"]
        direction TB
        
        subgraph Foundation["Foundation Module"]
            direction TB
            Build_Role["Build Instance Role<br/>aws_iam_role.build"]:::foundation
            Build_Profile["Build Instance Profile<br/>aws_iam_instance_profile.build"]:::foundation
            Build_SG["Build Security Group<br/>No Ingress, HTTP/HTTPS Egress"]:::foundation
            SNS_Topic["SNS Topic: Build Events<br/>aws_sns_topic.builds"]:::foundation
            Lifecycle_Role["Lifecycle Role<br/>aws_iam_role.lifecycle"]:::foundation
            Exec_Role["Image Builder Execution Role<br/>aws_iam_role.imagebuilder_execution"]:::foundation
        end

        subgraph Components["Custom Components Module"]
            direction TB
            Linux_SSM["linux-ssm-agent<br/>Installs/Upgrades SSM Agent"]:::component
            Linux_Hardening["linux-hardening<br/>Extra RHEL Hardening"]:::component
            Linux_Validate["linux-validate<br/>RHEL Validation Tests"]:::component
            Win_SSM["windows-ssm-agent<br/>Checks SSM Agent Version"]:::component
            Win_Hardening["windows-hardening<br/>Extra Windows Hardening"]:::component
            Win_Validate["windows-validate<br/>Windows Validation Tests"]:::component
        end

        subgraph Pipelines["Golden Image Pipelines (per OS)"]
            direction TB
            
            subgraph RHEL8["RHEL 8 Pipeline"]
                RHEL8_Recipe["Image Recipe<br/>Parent: RHEL 8 Base"]:::pipeline
                RHEL8_Infra["Infrastructure Config<br/>Subnet, SG, Key Pair"]:::pipeline
                RHEL8_Dist["Distribution Config<br/>AMI Naming + Cross-Account"]:::pipeline
                RHEL8_Pipe["Image Pipeline<br/>Links Recipe+Infra+Dist"]:::pipeline
                RHEL8_LC["Lifecycle Policy<br/>Retain 3 AMIs"]:::pipeline
            end
            
            subgraph RHEL9["RHEL 9 Pipeline"]
                RHEL9_Recipe["Image Recipe<br/>Parent: RHEL 9 Base"]:::pipeline
                RHEL9_Infra["Infrastructure Config"]:::pipeline
                RHEL9_Dist["Distribution Config"]:::pipeline
                RHEL9_Pipe["Image Pipeline"]:::pipeline
                RHEL9_LC["Lifecycle Policy"]:::pipeline
            end
            
            subgraph RHEL10["RHEL 10 Pipeline"]
                RHEL10_Recipe["Image Recipe<br/>Parent: RHEL 10 Base"]:::pipeline
                RHEL10_Infra["Infrastructure Config"]:::pipeline
                RHEL10_Dist["Distribution Config"]:::pipeline
                RHEL10_Pipe["Image Pipeline"]:::pipeline
                RHEL10_LC["Lifecycle Policy"]:::pipeline
            end
            
            subgraph Win2022["Windows Server 2022 Pipeline"]
                W22_Recipe["Image Recipe<br/>Parent: Win 2022 Base"]:::pipeline
                W22_Infra["Infrastructure Config"]:::pipeline
                W22_Dist["Distribution Config"]:::pipeline
                W22_Pipe["Image Pipeline"]:::pipeline
                W22_LC["Lifecycle Policy"]:::pipeline
            end
            
            subgraph Win2025["Windows Server 2025 Pipeline"]
                W25_Recipe["Image Recipe<br/>Parent: Win 2025 Base"]:::pipeline
                W25_Infra["Infrastructure Config"]:::pipeline
                W25_Dist["Distribution Config"]:::pipeline
                W25_Pipe["Image Pipeline"]:::pipeline
                W25_LC["Lifecycle Policy"]:::pipeline
            end
        end

        %% AWS Services in Dev Account
        Image_Builder["EC2 Image Builder Service"]:::aws_service
        EC2_Build["EC2 Build Instances<br/>(Private Subnet + NAT)"]:::aws_service
        SSM_Param_Build["SSM Parameter Store<br/>/golden-ami/{os}/latest"]:::aws_service
        S3_Logs["S3 Bucket: Logs<br/>jcp-infra-nonprod"]:::aws_service
        KMS["KMS Key (Optional)<br/>alias/aws/ebs"]:::aws_service
    end

    subgraph Prod_Account["Production Account (774133226694) - TARGET ACCOUNT"]
        direction TB
        Prod_SSM["SSM Parameter Store<br/>/golden-ami/{os}/latest<br/>(Replicated)"]:::target
        Prod_AMI["Shared AMIs<br/>Launch Permissions"]:::target
    end

    %% Connections - Deployment Flow
    User -->|1. Configure| Terraform_CLI
    Terraform_CLI -->|2. AssumeRole| Mgmt_Profile
    Mgmt_Profile -->|3. Assumes| TerraformDeploymentRole[("TerraformDeploymentRole<br/>in Dev Account")]:::external
    TerraformDeploymentRole -->|4. Deploys| Foundation
    TerraformDeploymentRole -->|4. Deploys| Components
    TerraformDeploymentRole -->|4. Deploys| Pipelines

    %% GitHub Actions Flow
    GH_Actions -->|Scheduled / Manual| TerraformDeploymentRole
    GH_Actions -.->|Uses| AWS_ROLE_ARN[("GitHub Secret: AWS_ROLE_ARN")]:::external

    %% Runtime Flow - Build Process
    RHEL8_Pipe -.->|Triggers| Image_Builder
    RHEL9_Pipe -.->|Triggers| Image_Builder
    RHEL10_Pipe -.->|Triggers| Image_Builder
    W22_Pipe -.->|Triggers| Image_Builder
    W25_Pipe -.->|Triggers| Image_Builder

    Image_Builder -->|Launches| EC2_Build
    EC2_Build -->|Uses| Build_Role
    EC2_Build -->|Uses| Build_Profile
    EC2_Build -->|Secured by| Build_SG
    EC2_Build -->|Downloads Components| Components
    EC2_Build -->|Executes Component Chain| Image_Builder
    
    %% Component Chain Execution Order
    Image_Builder -->|1. OS Patches| Update["update-linux/windows"]
    Image_Builder -->|2. AWS CLI v2| AWSCLI["aws-cli-version-2"]
    Image_Builder -->|3. SSM Agent| Linux_SSM
    Image_Builder -->|3. SSM Agent| Win_SSM
    Image_Builder -->|4. STIG Hardening| STIG["stig-build-linux/windows"]
    Image_Builder -->|5. Extra Hardening| Linux_Hardening
    Image_Builder -->|5. Extra Hardening| Win_Hardening
    Image_Builder -->|6. Validation| Linux_Validate
    Image_Builder -->|6. Validation| Win_Validate
    Image_Builder -->|7. CloudWatch Agent| CW["amazon-cloudwatch-agent"]
    Image_Builder -->|8. Boot Test| BootTest["simple-boot-test"]

    %% Distribution Flow
    Image_Builder -->|Builds AMI| RHEL8_Dist
    Image_Builder -->|Builds AMI| RHEL9_Dist
    Image_Builder -->|Builds AMI| RHEL10_Dist
    Image_Builder -->|Builds AMI| W22_Dist
    Image_Builder -->|Builds AMI| W25_Dist

    RHEL8_Dist -->|Shares AMI| Prod_AMI
    RHEL9_Dist -->|Shares AMI| Prod_AMI
    RHEL10_Dist -->|Shares AMI| Prod_AMI
    W22_Dist -->|Shares AMI| Prod_AMI
    W25_Dist -->|Shares AMI| Prod_AMI

    RHEL8_Dist -->|Writes SSM Param| SSM_Param_Build
    RHEL9_Dist -->|Writes SSM Param| SSM_Param_Build
    RHEL10_Dist -->|Writes SSM Param| SSM_Param_Build
    W22_Dist -->|Writes SSM Param| SSM_Param_Build
    W25_Dist -->|Writes SSM Param| SSM_Param_Build

    RHEL8_Dist -.->|Replicates SSM Param| Prod_SSM
    RHEL9_Dist -.->|Replicates SSM Param| Prod_SSM
    RHEL10_Dist -.->|Replicates SSM Param| Prod_SSM
    W22_Dist -.->|Replicates SSM Param| Prod_SSM
    W25_Dist -.->|Replicates SSM Param| Prod_SSM

    %% Logging & Notifications
    EC2_Build -->|Logs| S3_Logs
    EC2_Build -->|KMS Encryption (Optional)| KMS
    Image_Builder -->|Notifications| SNS_Topic
    SNS_Topic -->|Email| User

    %% Lifecycle Management
    Lifecycle_Role -->|Manages| RHEL8_LC
    Lifecycle_Role -->|Manages| RHEL9_LC
    Lifecycle_Role -->|Manages| RHEL10_LC
    Lifecycle_Role -->|Manages| W22_LC
    Lifecycle_Role -->|Manages| W25_LC

    RHEL8_LC -->|Deletes Old AMIs/Snapshots| Image_Builder
    RHEL9_LC -->|Deletes Old AMIs/Snapshots| Image_Builder
    RHEL10_LC -->|Deletes Old AMIs/Snapshots| Image_Builder
    W22_LC -->|Deletes Old AMIs/Snapshots| Image_Builder
    W25_LC -->|Deletes Old AMIs/Snapshots| Image_Builder

    %% Execution Role Permissions
    Exec_Role -->|Used by Image Builder| Image_Builder
    Exec_Role -->|SSM PutParameter| SSM_Param_Build
    Exec_Role -->|SSM PutParameter (Cross-Account)| Prod_SSM
    Exec_Role -->|EC2 AMI Operations| Image_Builder
    Exec_Role -->|KMS (if encrypted)| KMS
    Exec_Role -->|S3 Logs| S3_Logs
    Exec_Role -->|SNS Publish| SNS_Topic
    Exec_Role -->|IAM PassRole| Build_Role

    %% Styling
    classDef external fill:#fef3c7,stroke:#f59e0b,stroke-width:2px,color:#92400e
    classDef mgmt fill:#dbeafe,stroke:#3b82f6,stroke-width:2px,color:#1e40af
    classDef foundation fill:#e0e7ff,stroke:#6366f1,stroke-width:2px,color:#312e81
    classDef component fill:#fce7f3,stroke:#ec4899,stroke-width:2px,color:#9d174d
    classDef pipeline fill:#dcfce7,stroke:#22c55e,stroke-width:2px,color:#166534
    classDef aws_service fill:#f3f4f6,stroke:#6b7280,stroke-width:2px,color:#374151
    classDef target fill:#fee2e2,stroke:#ef4444,stroke-width:2px,color:#991b1b
```

## Draw.io Diagram

The draw.io diagram is saved as a separate `.drawio` XML file. You can open it directly in [draw.io](https://app.diagrams.net/) or any compatible diagram tool.

### How to Use the draw.io File

1. **Option 1**: Copy the contents of `architecture.drawio` and save as `.drawio` file, then open in draw.io
2. **Option 2**: Go to https://app.diagrams.net/ → File → Import From → Device → Select the `.drawio` file
3. **Option 3**: In VS Code, install "Draw.io Integration" extension and open the `.drawio` file directly

The draw.io file contains the same architecture with:
- Visual account boundaries (Management, Development, Production)
- Module groupings (Foundation, Components, Pipelines)
- Detailed component chain execution order
- Cross-account sharing flow
- IAM roles and permissions
- Data flows (AMI, SSM Parameters, Logs, Notifications)

---

## Component Chain Execution Order (Reference)

### Linux (RHEL 8/9/10)
```
1. update-linux                    → OS Patches
2. aws-cli-version-2-linux         → AWS CLI v2
3. linux-ssm-agent (Custom)        → Install/Upgrade SSM Agent
4. stig-build-linux                → STIG Hardening (Level: Low/Medium/High)
5. linux-hardening (Custom)        → Extra RHEL Hardening
6. linux-validate (Custom)         → RHEL Baseline Validation
7. amazon-cloudwatch-agent-linux   → CloudWatch Agent Installation (AWS Managed)
8. simple-boot-test-linux          → Boot Verification (AWS Managed)
```

### Windows (Server 2022/2025)
```
1. update-windows                  → OS Patches
2. aws-cli-version-2-windows       → AWS CLI v2
3. windows-ssm-agent (Custom)      → Check/Report SSM Agent Version
4. stig-build-windows              → STIG Hardening (Level: Low/Medium/High)
5. windows-hardening (Custom)      → Extra Windows Hardening
6. windows-validate (Custom)       → Windows Baseline Validation
7. amazon-cloudwatch-agent-windows → CloudWatch Agent Installation (AWS Managed)
8. simple-boot-test-windows        → Boot Verification (AWS Managed)
```

---

## Key Cross-Account Flows

| Flow | Source | Target | Mechanism |
|------|--------|--------|-----------|
| AMI Sharing | Dev (732533289325) | Prod (774133226694) | Image Builder Native `target_account_ids` |
| SSM Parameter (Build) | Dev | Dev | `ssm_parameter_configuration` in distribution |
| SSM Parameter (Target) | Dev | Prod | Dynamic `ssm_parameter_configuration` per target account |
| Lifecycle Cleanup | Dev | Dev | Lifecycle Policy with `AWSServiceRoleForImageBuilder` |
| Notifications | Dev | Email | SNS Topic + Email Subscriptions |

---

## Required GitHub Secrets

| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN` | `arn:aws:iam::732533289325:role/TerraformDeploymentRole` |
| `AWS_REGION` | `us-east-1` |

---

## Deployment Commands

```bash
cd golden-ami-factory/environments/prod

# 1. Initialize
terraform init -backend-config=backend.hcl

# 2. Foundation (IAM, SG, SNS)
terraform plan -target=module.foundation
terraform apply -target=module.foundation

# 3. Custom Components
terraform plan -target=module.components
terraform apply -target=module.components

# 4. Golden Image Pipelines
terraform plan
terraform apply
```

---

## Verification Commands

```bash
# Check SSM Parameter (in any account)
aws ssm get-parameter --name "/golden-ami/rhel-9/latest" --region us-east-1

# Check Shared AMIs (in target account)
aws ec2 describe-images --owners 732533289325 --filters "Name=name,Values=jq-golden-ami-*"

# Trigger Pipeline Manually
aws imagebuilder start-image-pipeline-execution --image-pipeline-arn <arn>

# Check Pipeline Status
aws imagebuilder get-image --image-build-version-arn <arn> --query 'image.state'
```