module "foundation" {
  source = "../../modules/foundation"

  name_prefix           = local.name_prefix
  vpc_id                = var.vpc_id
  ssm_parameter_prefix  = var.ssm_parameter_prefix
  target_account_ids    = var.target_account_ids
  tags                  = local.common_tags
}

module "components" {
  source = "../../modules/components"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# Recipe Registry - declarative recipe definitions
module "recipe_registry" {
  source                      = "../../modules/recipe_registry"
  recipes_path                = "${path.module}/../../modules/recipe_registry/recipes"
  custom_components_arns      = module.components.arns
  aws_managed_components_prefix = local.jq_prefix
  default_stig_level          = var.stig_level
  default_root_volume_size    = 100
  tags                        = local.common_tags
  enabled_recipes             = var.enabled_recipes
}

module "golden_image" {
  source   = "../../modules/golden_image"
  for_each = module.recipe_registry.recipes

  name_prefix                   = local.name_prefix
  os_key                        = each.key
  os_family                     = each.value.os_family
  display_name                  = each.value.name
  # Derive ami_os_code from recipe key (e.g., "rhel-9-stig-medium" -> "rhel9")
ami_os_code                   = replace(each.key, "-stig-(low|medium|high)", "")
  ami_name_prefix               = var.ami_name_prefix
  ami_architecture              = var.ami_architecture
  ami_date_token                = local.ami_date_token
  ami_release_version           = var.ami_release_version
  parent_image_arn              = each.value.parent_image_arn
  component_arns                = each.value.component_arns
  stig_component_arn            = each.value.stig_component_arn
  stig_level                    = each.value.stig_level
  root_volume_size              = each.value.root_volume_size
  ebs_encrypted                 = each.value.ebs_encrypted
  kms_key_arn                   = each.value.kms_key_arn != "" ? each.value.kms_key_arn : (var.ebs_encrypted ? data.aws_kms_alias.ebs[0].target_key_arn : "")

  instance_types                = each.value.os_family == "windows" ? var.windows_instance_types : var.linux_instance_types
  subnet_id                     = var.subnet_id
  key_pair_name                 = var.key_pair_name
  security_group_id             = module.foundation.security_group_id
  instance_profile_name         = module.foundation.instance_profile_name
  imagebuilder_execution_role_arn = module.foundation.imagebuilder_execution_role_arn

  ssm_parameter_name            = "${var.ssm_parameter_prefix}/${each.key}/latest"
  target_account_ids            = var.target_account_ids
  schedule_expression           = var.pipeline_schedule_expression
  images_to_retain              = each.value.lifecycle_policy_count
  lifecycle_role_arn            = module.foundation.lifecycle_role_arn
  tags                          = each.value.tags
}
