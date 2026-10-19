# Applied once, by hand, by an existing administrator:
#   - a KMS key for Terraform state
#   - one versioned, encrypted state bucket with native S3 locking (no DynamoDB)
#     readable only by hive-admin and the break-glass administrators
#   - envs/backend.hcl, which every other stack uses to find its state

data "aws_partition" "current" {}

locals {
  bucket_name = "hive-tfstate-${var.account_id}"
  iam_prefix  = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}"

  # hive-admin does not exist yet (the account stack creates it); a policy
  # condition on its ARN works before the role exists.
  state_principals = concat(
    ["${local.iam_prefix}:root", "${local.iam_prefix}:role/hive-admin"],
    var.break_glass_principal_arns,
  )
}

data "aws_iam_policy_document" "state_key" {
  #checkov:skip=CKV_AWS_109:Standard key administration statement for the account root; the bucket policy limits who reaches the state.
  #checkov:skip=CKV_AWS_111:Standard key administration statement for the account root; the bucket policy limits who reaches the state.
  #checkov:skip=CKV_AWS_356:In a key policy, "*" means this key only.
  statement {
    sid       = "AccountAdministersTheKey"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["${local.iam_prefix}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "Terraform state for HiveConnect"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.state_key.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/hive-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "keep-90-days-of-state-history"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "OnlyHiveAdminAndBreakGlass"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.state_principals
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "local_file" "backend_config" {
  filename        = "${path.module}/../envs/backend.hcl"
  file_permission = "0644"
  content         = <<-EOT
    # Written by bootstrap/. Shared by every stack; scripts/tf.sh adds the state key.
    bucket       = "${aws_s3_bucket.state.id}"
    region       = "${var.region}"
    encrypt      = true
    kms_key_id   = "${aws_kms_key.state.arn}"
    use_lockfile = true
  EOT
}
