output "pipeline_arn" {
  value = aws_imagebuilder_image_pipeline.this.arn
}

output "recipe_arn" {
  value = aws_imagebuilder_image_recipe.this.arn
}

output "ssm_parameter_name" {
  value = var.ssm_parameter_name
}

output "ami_name_template" {
  value = local.ami_name
}
