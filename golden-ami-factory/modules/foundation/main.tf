data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Build instance role + profile
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "build" {
  name               = "${var.name_prefix}-build-role"
  description        = "Instance role used by EC2 Image Builder build and test instances"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.build.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "image_builder" {
  role       = aws_iam_role.build.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "image_builder_ecr_container_builds" {
  role       = aws_iam_role.build.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
}

resource "aws_iam_instance_profile" "build" {
  name = "${var.name_prefix}-build-profile"
  role = aws_iam_role.build.name
  tags = var.tags
}

# ---------------------------------------------------------------------------
# Build instance security group: no inbound, HTTP/HTTPS outbound only
# ---------------------------------------------------------------------------
resource "aws_security_group" "build" {
  name        = "${var.name_prefix}-build-sg"
  description = "Image Builder build instances: no ingress, web egress only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-build-sg" })

  # Remove default allow-all egress rule; we manage egress via aws_vpc_security_group_egress_rule resources
  egress = []
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.build.id
  description       = "HTTPS to SSM, package repositories"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.build.id
  description       = "HTTP for OS update mirrors"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Lifecycle policy execution role (old AMI + snapshot clean-up)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "imagebuilder_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["imagebuilder.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lifecycle" {
  name               = "${var.name_prefix}-lifecycle-role"
  description        = "Execution role for Image Builder lifecycle policies"
  assume_role_policy = data.aws_iam_policy_document.imagebuilder_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lifecycle" {
  role       = aws_iam_role.lifecycle.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/EC2ImageBuilderLifecycleExecutionPolicy"
}

# ---------------------------------------------------------------------------
# Image Builder execution role (used during image distribution/integration)
# ---------------------------------------------------------------------------
# This role replaces the AWSServiceRoleForImageBuilder service-linked role
# and provides necessary SSM permissions to write the AMI ID to SSM parameters.
data "aws_iam_policy_document" "imagebuilder_execution" {
  statement {
    sid = "SSMPutParameter"
    actions = [
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:SendCommand",
      "ssm:DescribeParameters"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_prefix}/*"
    ]
  }
  statement {
    sid = "EC2ImageBuilderFullAccess"
    actions = [
      "imagebuilder:*"
    ]
    resources = ["*"]
  }
  statement {
    sid = "EC2ActionsForDistribution"
    actions = [
      "ec2:CreateImage",
      "ec2:CopyImage",
      "ec2:ModifyImageAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:DeregisterImage",
      "ec2:DescribeImages",
      "ec2:DescribeSnapshots",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:CreateTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeImages",
      "ec2:CreateLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes"
    ]
    resources = ["*"]
  }
  dynamic "statement" {
    for_each = length(var.target_account_ids) > 0 ? [1] : []
    content {
      sid     = "AllowAssumeDistributionCrossAccountRole"
      actions = ["sts:AssumeRole"]
      resources = [for account_id in var.target_account_ids : "arn:${data.aws_partition.current.partition}:iam::${account_id}:role/EC2ImageBuilderDistributionCrossAccountRole"]
    }
  }
  statement {
    sid = "KMSForEncryptedAMIs"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:kms:*:${data.aws_caller_identity.current.account_id}:key/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.*.amazonaws.com"]
    }
  }
  statement {
    sid     = "IAMPassRole"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-build-role"
    ]
  }
  statement {
    sid     = "IAMGetRole"
    actions = ["iam:GetRole", "iam:GetInstanceProfile"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-build-role",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.name_prefix}-build-profile"
    ]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "imagebuilder_execution" {
  name               = "${var.name_prefix}-imagebuilder-execution-role"
  description        = "Execution role for EC2 Image Builder image distribution and integration"
  assume_role_policy = data.aws_iam_policy_document.imagebuilder_trust.json
  tags               = var.tags
}

# Attach AWS managed policy for correct SSM SendCommand permissions
# This grants the properly-scoped ssm:SendCommand, ssm:GetCommandInvocation,
# ssm:ListCommandInvocations and other orchestration permissions Image Builder needs.
resource "aws_iam_role_policy_attachment" "imagebuilder_execution_managed" {
  role       = aws_iam_role.imagebuilder_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/EC2ImageBuilderExecutionPolicy"
}

resource "aws_iam_role_policy" "imagebuilder_execution" {
  name   = "imagebuilder-execution-policy"
  role   = aws_iam_role.imagebuilder_execution.id
  policy = data.aws_iam_policy_document.imagebuilder_execution.json
}
