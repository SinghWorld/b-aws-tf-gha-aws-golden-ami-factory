# Recipe Registry Module
# Reads declarative YAML recipe definitions and produces normalized recipe configurations
# for the golden_image module.

# Discover all recipe YAML files in the recipes directory
data "local_file" "recipe_files" {
  filename = "${var.recipes_path}/index.yaml"
}

locals {
  # Get recipes from index.yaml
  index_recipes = try(yamldecode(data.local_file.recipe_files.content).recipes, [])

  # Use enabled_recipes if specified, otherwise use all from index
  recipe_index = length(var.enabled_recipes) > 0 ? var.enabled_recipes : local.index_recipes

  # Read each recipe YAML file as raw string for template interpolation
  recipe_raw_configs = {
    for recipe_key in local.recipe_index :
    recipe_key => file("${var.recipes_path}/${recipe_key}.yaml")
  }

  # Template variables for interpolation
  template_vars = {
    aws_managed_components_prefix = var.aws_managed_components_prefix
    custom_components_arns        = var.custom_components_arns
    default_stig_level            = var.default_stig_level
    default_root_volume_size      = var.default_root_volume_size
  }

  # Interpolate template variables in recipe YAML
  recipe_interpolated = {
    for key, raw in local.recipe_raw_configs :
    key => templatefile("${var.recipes_path}/${key}.yaml", local.template_vars)
  }

  # Parse interpolated YAML
  recipe_configs = {
    for key, interpolated in local.recipe_interpolated :
    key => yamldecode(interpolated)
  }

  # Normalize and validate each recipe
  normalized_recipes = {
    for key, config in local.recipe_configs :
    key => {
      # Required fields
      name               = config.name
      description        = config.description
      os_family          = config.os_family
      parent_image_arn   = config.parent_image_arn
      component_chain    = config.component_chain

      # Optional fields with defaults
      stig_level                    = coalesce(config.stig_level, var.default_stig_level)
      root_volume_size              = coalesce(config.root_volume_size, var.default_root_volume_size)
      root_device_name              = coalesce(config.root_device_name, "/dev/sda1")
      ebs_encrypted                 = coalesce(config.ebs_encrypted, false)
      kms_key_arn                   = config.kms_key_arn
      block_device_mappings         = coalesce(config.block_device_mappings, [])
      ami_name_suffix               = config.ami_name_suffix
      distribution_regions          = coalesce(config.distribution_regions, [])
      lifecycle_policy_count        = coalesce(config.lifecycle_policy_count, 3)
      tags                          = merge(var.tags, config.tags)

      # Computed fields
      stig_component_arn = config.stig_component_arn
    }
  }

  # Extract component ARNs from component_chain for golden_image module
  recipes_with_component_arns = {
    for key, recipe in local.normalized_recipes :
    key => merge(recipe, {
      component_arns = [for c in recipe.component_chain : c.arn]
    })
  }

  # Validate os_family - use a local value that can be checked
  validation_errors = [
    for key, recipe in local.normalized_recipes :
    "Recipe ${key}: os_family must be 'linux' or 'windows', got '${recipe.os_family}'"
    if !contains(["linux", "windows"], recipe.os_family)
  ]

  # Simple validation output - will be empty if no errors
  validation_result = join("\n", local.validation_errors)
}

# Output the normalized recipes for consumption by golden_image module
output "recipes" {
  description = "Map of normalized recipe configurations keyed by recipe key."
  value       = local.recipes_with_component_arns
}

output "recipe_keys" {
  description = "List of enabled recipe keys."
  value       = local.recipe_index
}