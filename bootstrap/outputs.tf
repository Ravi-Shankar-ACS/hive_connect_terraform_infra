output "state_bucket" {
  description = "Terraform state bucket."
  value       = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  description = "KMS key that encrypts the state."
  value       = aws_kms_key.state.arn
}
