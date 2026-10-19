# Human roles. Engineers sign in as their own IAM user with MFA and assume one
# of these for an hour. Nobody creates an access key for this build.
#
#   hive-admin      create and change hive-* infrastructure with Terraform
#   hive-developer  push images, restart services, read logs, ECS Exec
#   hive-readonly   view only

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  roles = {
    admin = {
      users       = var.admin_user_arns
      description = "Create and change the hive-* infrastructure with Terraform"
      managed     = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"]
    }
    developer = {
      users       = var.developer_user_arns
      description = "Push images, update services, read logs and use ECS Exec"
      managed     = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/ViewOnlyAccess"]
    }
    readonly = {
      users       = var.readonly_user_arns
      description = "View only"
      managed     = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/ViewOnlyAccess"]
    }
  }

  # Roles with nobody to assume them are not created.
  active_roles = { for k, v in local.roles : k => v if length(v.users) > 0 }

  attachments = merge([
    for k, v in local.active_roles : { for arn in v.managed : "${k}:${arn}" => { role = k, arn = arn } }
  ]...)
}

data "aws_iam_policy_document" "trust" {
  for_each = local.active_roles

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = each.value.users
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.active_roles

  name                 = "hive-${each.key}"
  description          = each.value.description
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = var.session_duration_seconds
  permissions_boundary = aws_iam_policy.boundary.arn
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = local.attachments

  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}

# --- hive-developer -------------------------------------------------------

data "aws_iam_policy_document" "developer" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken and logs:GetQueryResults do not support resource-level permissions.
  statement {
    sid       = "EcrSignIn"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushAndPullHiveImages"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImages", "ecr:DescribeImageScanFindings", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:ListImages", "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ecr:${local.region}:${local.account_id}:repository/hive-*"]
  }

  statement {
    sid       = "RestartHiveServices"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:${data.aws_partition.current.partition}:ecs:${local.region}:${local.account_id}:service/hive-*/*"]
  }

  statement {
    sid     = "EcsExecAndTasks"
    actions = ["ecs:ExecuteCommand", "ecs:DescribeTasks", "ecs:StopTask"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ecs:${local.region}:${local.account_id}:cluster/hive-*",
      "arn:${data.aws_partition.current.partition}:ecs:${local.region}:${local.account_id}:task/hive-*/*",
    ]
  }

  statement {
    sid = "ReadHiveLogs"
    actions = [
      "logs:GetLogEvents", "logs:FilterLogEvents", "logs:StartQuery", "logs:StartLiveTail",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:/hive-*"]
  }

  statement {
    sid       = "LogQueryResults"
    actions   = ["logs:GetQueryResults"]
    resources = ["*"]
  }

  # ECS Exec sessions are encrypted with each environment's "app" key.
  statement {
    sid       = "EcsExecSessionEncryption"
    actions   = ["kms:GenerateDataKey"]
    resources = ["arn:${data.aws_partition.current.partition}:kms:${local.region}:${local.account_id}:key/*"]

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "kms:ResourceAliases"
      values   = ["alias/hive-*-app"]
    }
  }
}

resource "aws_iam_policy" "developer" {
  count = contains(keys(local.active_roles), "developer") ? 1 : 0

  name        = "hive-developer-access"
  description = "What hive-developer may change: hive images, services, logs and ECS Exec."
  policy      = data.aws_iam_policy_document.developer.json
}

resource "aws_iam_role_policy_attachment" "developer" {
  count = contains(keys(local.active_roles), "developer") ? 1 : 0

  role       = aws_iam_role.this["developer"].name
  policy_arn = aws_iam_policy.developer[0].arn
}
