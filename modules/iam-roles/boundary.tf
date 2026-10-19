# The permission boundary on every hive-* role, human or service. A boundary is
# a ceiling: it grants nothing by itself, it only removes what is denied here,
# whatever the role's own policies say.
#
# What it guarantees:
# - The running EKS, Aurora, load balancers and Alexa instance cannot be changed.
# - The default VPC (where the Alexa instance runs) cannot be changed.
# - No IAM users or access keys can be created.
# - IAM changes are limited to hive-* roles and policies, every new role must
#   carry this boundary, and the guardrails themselves cannot be edited.
# - Account-wide settings (S3 Block Public Access, CloudTrail, GuardDuty,
#   Config) cannot be switched off or on from a hive-* role.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_vpcs" "default" {
  filter {
    name   = "is-default"
    values = ["true"]
  }
}

locals {
  iam_prefix   = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"
  boundary_arn = "${local.iam_prefix}:policy/hive-boundary"

  default_vpc_arns = [
    for id in data.aws_vpcs.default.ids :
    "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:vpc/${id}"
  ]

  guardrail_arns = [
    local.boundary_arn,
    "${local.iam_prefix}:policy/hive-developer-access",
    "${local.iam_prefix}:role/hive-admin",
    "${local.iam_prefix}:role/hive-developer",
    "${local.iam_prefix}:role/hive-readonly",
    "${local.iam_prefix}:role/hive-account-*",
  ]

  iam_write_actions = [
    "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateRoleDescription",
    "iam:UpdateAssumeRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PutRolePermissionsBoundary",
    "iam:TagRole", "iam:UntagRole",
    "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion",
    "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:TagPolicy", "iam:UntagPolicy",
  ]

  # On protected resources everything is denied except reading them.
  read_only_actions = [
    "ec2:Describe*", "ec2:Get*", "eks:Describe*", "eks:List*",
    "rds:Describe*", "rds:List*", "rds:Download*", "elasticloadbalancing:Describe*",
  ]
}

data "aws_iam_policy_document" "boundary" {
  #checkov:skip=CKV_AWS_1:A permission boundary is a ceiling; the explicit denies below do the restricting.
  #checkov:skip=CKV_AWS_49:A permission boundary is a ceiling; the explicit denies below do the restricting.
  #checkov:skip=CKV_AWS_107:A permission boundary is a ceiling; it grants nothing on its own.
  #checkov:skip=CKV_AWS_108:A permission boundary is a ceiling; it grants nothing on its own.
  #checkov:skip=CKV_AWS_109:A permission boundary is a ceiling; it grants nothing on its own.
  #checkov:skip=CKV_AWS_110:A permission boundary is a ceiling; it grants nothing on its own.
  #checkov:skip=CKV_AWS_111:A permission boundary is a ceiling; it grants nothing on its own.
  #checkov:skip=CKV_AWS_356:A permission boundary is a ceiling; it grants nothing on its own.
  #checkov:skip=CKV2_AWS_40:A permission boundary is a ceiling; it grants nothing on its own.
  statement {
    sid       = "Ceiling"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid         = "ProtectTheRunningStack"
    effect      = "Deny"
    not_actions = local.read_only_actions
    resources   = concat(var.protected_resource_arns, local.default_vpc_arns)
  }

  dynamic "statement" {
    for_each = length(local.default_vpc_arns) > 0 ? [1] : []
    content {
      sid         = "ProtectResourcesInTheDefaultVpc"
      effect      = "Deny"
      not_actions = local.read_only_actions
      resources   = ["*"]

      condition {
        test     = "ArnEquals"
        variable = "ec2:Vpc"
        values   = local.default_vpc_arns
      }
    }
  }

  statement {
    sid    = "NoIamUsersOrAccessKeys"
    effect = "Deny"
    actions = [
      "iam:CreateUser", "iam:DeleteUser", "iam:CreateAccessKey", "iam:UpdateAccessKey",
      "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:AttachUserPolicy",
      "iam:PutUserPolicy", "iam:AddUserToGroup", "iam:CreateGroup", "iam:AttachGroupPolicy",
      "iam:PutGroupPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid           = "IamOnlyForHiveRolesAndPolicies"
    effect        = "Deny"
    actions       = local.iam_write_actions
    not_resources = ["${local.iam_prefix}:role/hive-*", "${local.iam_prefix}:policy/hive-*"]
  }

  statement {
    sid           = "PassOnlyHiveRoles"
    effect        = "Deny"
    actions       = ["iam:PassRole"]
    not_resources = ["${local.iam_prefix}:role/hive-*"]
  }

  statement {
    sid       = "NewRolesMustCarryThisBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid       = "NobodyRemovesABoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid         = "GuardrailsAreReadOnly"
    effect      = "Deny"
    not_actions = ["iam:Get*", "iam:List*", "sts:AssumeRole"]
    resources   = local.guardrail_arns
  }

  statement {
    sid    = "NoAccountWideSwitches"
    effect = "Deny"
    actions = [
      "s3:PutAccountPublicAccessBlock",
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors",
      "guardduty:DeleteDetector", "guardduty:UpdateDetector", "guardduty:CreateDetector",
      "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:PutConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "access-analyzer:DeleteAnalyzer",
      "inspector2:Disable", "ecr:PutRegistryScanningConfiguration",
      "ce:UpdateCostAllocationTagsStatus",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "hive-boundary"
  description = "Permission boundary for every hive-* role: protects the running stack and the account guardrails."
  policy      = data.aws_iam_policy_document.boundary.json
}
