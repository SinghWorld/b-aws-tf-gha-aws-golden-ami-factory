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
