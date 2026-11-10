output "instance_profile_name" {
  value = aws_iam_instance_profile.build.name
}

output "security_group_id" {
  value = aws_security_group.build.id
}

output "lifecycle_role_arn" {
  value = aws_iam_role.lifecycle.arn
}

output "imagebuilder_execution_role_arn" {
  value = aws_iam_role.imagebuilder_execution.arn
}
