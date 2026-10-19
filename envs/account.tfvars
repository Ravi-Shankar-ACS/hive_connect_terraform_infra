# Account-wide settings, shared by UAT and production.
# Applied by the break-glass administrator: scripts/tf.sh account plan|apply
# Run scripts/preflight.sh first; it prints most of the values below.

account_id = "123456789012" # TODO: the existing AWS account ID
region     = "ap-south-1"

# --- Who may assume which role (IAM users with MFA) --------------------------
# Plan open question 5.
admin_user_arns = [
  "arn:aws:iam::123456789012:user/CHANGE-ME", # TODO
]
developer_user_arns = []
readonly_user_arns  = []

# --- The running stack that hive-* roles may never change ---------------------
# TODO: replace with the real ARNs printed by scripts/preflight.sh.
protected_resource_arns = [
  "arn:aws:eks:ap-south-1:123456789012:cluster/OLD-EKS-CLUSTER",
  "arn:aws:eks:ap-south-1:123456789012:nodegroup/OLD-EKS-CLUSTER/*",
  "arn:aws:rds:ap-south-1:123456789012:cluster:OLD-AURORA-CLUSTER",
  "arn:aws:rds:ap-south-1:123456789012:db:OLD-AURORA-INSTANCE-*",
  "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/OLD-ALB/*",
  "arn:aws:elasticloadbalancing:ap-south-1:123456789012:listener/app/OLD-ALB/*",
  "arn:aws:elasticloadbalancing:ap-south-1:123456789012:listener-rule/app/OLD-ALB/*",
  "arn:aws:ec2:ap-south-1:123456789012:instance/i-ALEXA-INSTANCE",
]

alert_emails = ["CHANGE-ME@example.com"] # TODO

# --- Security baseline: set false for anything preflight shows is already on --
enable_guardduty       = true
enable_config          = true
enable_access_analyzer = true
enable_cloudtrail      = true
enable_inspector_ecr   = true

# GuardDuty protection plans bill on the whole account, old stack included.
# Read the usage during the 30-day trial (plan section 8) and switch off what
# costs more than it is worth.
guardduty_features = {
  S3_DATA_EVENTS         = "ENABLED"
  RDS_LOGIN_EVENTS       = "ENABLED"
  EKS_AUDIT_LOGS         = "DISABLED"
  EBS_MALWARE_PROTECTION = "DISABLED"
  LAMBDA_NETWORK_LOGS    = "DISABLED"
  RUNTIME_MONITORING     = "DISABLED"
}

# Add the old stack's ECR repositories here if it uses ECR, so they keep being scanned.
inspector_ecr_repository_filters = ["hive-*"]

# Set true about a day after the first uat/network apply, then apply again.
activate_cost_tags = false
