module "foundation" {
  source = "../../modules/foundation"

  name_prefix          = local.name_prefix
  vpc_id               = var.vpc_id
  log_bucket_name      = var.log_bucket_name
  log_bucket_prefix    = var.log_bucket_prefix
  notification_emails  = var.notification_emails
  ssm_parameter_prefix = var.ssm_parameter_prefix
  tags                 = local.common_tags
}

module "components" {
  source = "../../modules/components"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "golden_image" {
  source   = "../../modules/golden_image"
  for_each = local.enabled_os

  name_prefix         = local.name_prefix
  os_key              = each.key
  os_family           = each.value.family
  display_name        = each.value.display
  ami_os_code         = each.value.ami_os_code
  ami_name_prefix     = var.ami_name_prefix
  ami_architecture    = var.ami_architecture
  ami_date_token      = local.ami_date_token
  ami_release_version = var.ami_release_version
  parent_image_arn    = "${local.jq_prefix}:image/${each.value.parent}/x.x.x"
  component_arns      = local.component_chain[each.value.family]
  stig_component_arn  = "${local.jq_prefix}:component/stig-build-${each.value.family}/x.x.x"
  stig_level          = var.stig_level
  root_volume_size    = each.value.volume_gb
  kms_key_arn         = data.aws_kms_alias.ebs.target_key_arn

  instance_types                  = each.value.family == "windows" ? var.windows_instance_types : var.linux_instance_types
  subnet_id                       = var.subnet_id
  key_pair_name                   = var.key_pair_name
  security_group_id               = module.foundation.security_group_id
  instance_profile_name           = module.foundation.instance_profile_name
  sns_topic_arn                   = module.foundation.sns_topic_arn
  log_bucket_name                 = var.log_bucket_name
  log_bucket_prefix               = var.log_bucket_prefix
  imagebuilder_execution_role_arn = module.foundation.imagebuilder_execution_role_arn

  ssm_parameter_name  = "${var.ssm_parameter_prefix}/${each.key}/latest"
  target_account_ids  = var.target_account_ids
  schedule_expression = var.pipeline_schedule_expression
  images_to_retain    = var.images_to_retain
  lifecycle_role_arn  = module.foundation.lifecycle_role_arn
  tags                = local.common_tags
}
