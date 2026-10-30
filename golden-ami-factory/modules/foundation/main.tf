data "aws_partition" "current" {}

locals {
  logs_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.log_bucket_name}"
}

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

data "aws_iam_policy_document" "build_logs" {
  statement {
    sid       = "WriteBuildLogs"
    actions   = ["s3:PutObject"]
    resources = ["${local.logs_bucket_arn}/${var.log_bucket_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "build_logs" {
  name   = "write-build-logs"
  role   = aws_iam_role.build.id
  policy = data.aws_iam_policy_document.build_logs.json
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
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.build.id
  description       = "HTTPS to SSM, S3, package repositories"
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
# Build notifications
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "builds" {
  name = "${var.name_prefix}-build-events"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.notification_emails)
  topic_arn = aws_sns_topic.builds.arn
  protocol  = "email"
  endpoint  = each.value
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
    sid = "S3LogsAccess"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.log_bucket_name}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.log_bucket_name}/*"
    ]
  }
  statement {
    sid       = "SNSPublish"
    actions   = ["sns:Publish"]
    resources = ["arn:${data.aws_partition.current.partition}:sns:*:${data.aws_caller_identity.current.account_id}:*"]
  }
  statement {
    sid    = "IAMPassRole"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-build-role"
    ]
  }
  statement {
    sid    = "IAMGetRole"
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

resource "aws_iam_role_policy" "imagebuilder_execution" {
  name   = "imagebuilder-execution-policy"
  role   = aws_iam_role.imagebuilder_execution.id
  policy = data.aws_iam_policy_document.imagebuilder_execution.json
}
