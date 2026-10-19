# Outputs wait for the bucket policy, so services that test-write on setup
# (ALB access logs, WAF logging) never see a bucket without its policy.

output "id" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
  depends_on  = [aws_s3_bucket_policy.this, aws_s3_bucket_server_side_encryption_configuration.this]
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
  depends_on  = [aws_s3_bucket_policy.this, aws_s3_bucket_server_side_encryption_configuration.this]
}
