data "aws_region" "current" {}

locals {
  base_name         = "${var.name_prefix}-${var.os_key}"
  ami_name          = "${var.ami_name_prefix}-${var.ami_os_code}-${var.ami_architecture}-${var.ami_date_token}.${var.ami_release_version}-{{ imagebuilder:buildDate }}"
  ami_name_tag      = "${var.ami_name_prefix}-${var.ami_os_code}-${var.ami_architecture}-${var.ami_date_token}.${var.ami_release_version}"
  imagebuilder_tags = { for key, value in var.tags : key => value if lower(key) != "createdby" }

  # Recipes are immutable, so the name carries a hash of everything that defines
  # the recipe. Any change produces a fresh recipe instead of a version clash.
  recipe_hash = substr(sha1(jsonencode([var.parent_image_arn, var.component_arns, var.stig_level, var.root_volume_size, var.ebs_encrypted, var.kms_key_arn])), 0, 8)
}

resource "aws_imagebuilder_image_recipe" "this" {
  name         = "${local.base_name}-${local.recipe_hash}"
  version      = "1.0.0"
  parent_image = var.parent_image_arn
  description  = "${var.display_name} golden image recipe"
  tags         = var.tags

  block_device_mapping {
    device_name = var.root_device_name
    ebs {
      delete_on_termination = true
      encrypted             = var.ebs_encrypted
      kms_key_id            = var.ebs_encrypted ? var.kms_key_arn : null
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
    }
  }

  dynamic "component" {
    for_each = var.component_arns
    content {
      component_arn = component.value

      dynamic "parameter" {
        for_each = component.value == var.stig_component_arn ? [var.stig_level] : []
        content {
          name  = "Level"
          value = title(parameter.value)
        }
      }
    }
  }

  # Image Builder supports this recipe setting for Linux, but rejects it for Windows.
  dynamic "systems_manager_agent" {
    for_each = var.os_family == "linux" ? [true] : []
    content {
      uninstall_after_build = false
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "this" {
  name                          = local.base_name
  description                   = "Build infrastructure for ${var.display_name}"
  instance_profile_name         = var.instance_profile_name
  instance_types                = var.instance_types
  key_pair                      = var.key_pair_name
  subnet_id                     = var.subnet_id
  security_group_ids            = [var.security_group_id]
  sns_topic_arn                 = var.sns_topic_arn
  terminate_instance_on_failure = true
  resource_tags                 = local.imagebuilder_tags
  tags                          = var.tags

  instance_metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  logging {
    s3_logs {
      s3_bucket_name = var.log_bucket_name
      s3_key_prefix  = "${var.log_bucket_prefix}/${var.os_key}"
    }
  }
}

resource "aws_imagebuilder_distribution_configuration" "this" {
  name        = local.base_name
  description = "Distribution for ${var.display_name}"
  tags        = var.tags

  distribution {
    region = data.aws_region.current.region

    ami_distribution_configuration {
      name               = local.ami_name
      description        = "${var.display_name} golden image ${var.ami_date_token}.${var.ami_release_version}"
      kms_key_id         = var.ebs_encrypted ? var.kms_key_arn : null
      target_account_ids = length(var.target_account_ids) > 0 ? var.target_account_ids : null
      ami_tags = merge(var.tags, {
        Name        = local.ami_name_tag
        OS          = var.os_key
        DateToken   = var.ami_date_token
        Release     = var.ami_release_version
        GoldenImage = var.os_key
      })
    }

    # Parameter in the build account. data_type aws:ec2:image makes Image Builder
    # validate the value and lets CloudFormation use the AWS::EC2::Image::Id type.
    ssm_parameter_configuration {
      parameter_name = var.ssm_parameter_name
      data_type      = "aws:ec2:image"
    }

    # Same parameter name inside every distribution account.
    dynamic "ssm_parameter_configuration" {
      for_each = toset(var.target_account_ids)
      content {
        ami_account_id = ssm_parameter_configuration.value
        parameter_name = var.ssm_parameter_name
        data_type      = "aws:ec2:image"
      }
    }
  }
}

resource "aws_imagebuilder_image_pipeline" "this" {
  name                             = local.base_name
  description                      = "${var.display_name} golden image pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.this.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this.arn
  execution_role                   = var.imagebuilder_execution_role_arn
  enhanced_image_metadata_enabled  = true
  status                           = "ENABLED"
  tags                             = var.tags

  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = var.test_timeout_minutes
  }

  dynamic "schedule" {
    for_each = var.schedule_expression == null ? [] : [var.schedule_expression]
    content {
      schedule_expression                = schedule.value
      timezone                           = var.schedule_timezone
      pipeline_execution_start_condition = "EXPRESSION_MATCH_ONLY"
    }
  }
}

# Keep the newest N images per OS and delete older AMIs with their snapshots.
resource "aws_imagebuilder_lifecycle_policy" "this" {
  count = var.images_to_retain > 0 ? 1 : 0

  name           = local.base_name
  description    = "Retain the newest ${var.images_to_retain} ${var.display_name} images"
  execution_role = var.lifecycle_role_arn
  resource_type  = "AMI_IMAGE"
  tags           = var.tags

  policy_detail {
    action {
      type = "DELETE"
      include_resources {
        amis      = true
        snapshots = true
      }
    }
    filter {
      type  = "COUNT"
      value = var.images_to_retain
    }
  }

  resource_selection {
    tag_map = {
      GoldenImage = var.os_key
    }
  }
}
