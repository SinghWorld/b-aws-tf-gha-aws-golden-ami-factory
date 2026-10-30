output "arns" {
  description = "Map of custom component key to ARN."
  value       = { for k, c in aws_imagebuilder_component.this : k => c.arn }
}
