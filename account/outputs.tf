output "boundary_arn" {
  description = "Permission boundary every hive-* role carries."
  value       = module.iam_roles.boundary_arn
}

output "role_arns" {
  description = "Roles engineers assume with MFA."
  value       = module.iam_roles.role_arns
}

output "switch_role_hint" {
  description = "How to assume hive-admin from the CLI."
  value       = "Add a profile with role_arn = ${lookup(module.iam_roles.role_arns, "hive-admin", "")}, source_profile = <your user>, mfa_serial = <your MFA device ARN>, duration_seconds = 3600 (see README)."
}
