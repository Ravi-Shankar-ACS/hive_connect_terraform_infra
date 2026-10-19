output "boundary_arn" {
  description = "Permission boundary every hive-* role must carry."
  value       = aws_iam_policy.boundary.arn
}

output "role_arns" {
  description = "Human role name => ARN."
  value       = { for k, r in aws_iam_role.this : r.name => r.arn }
}
