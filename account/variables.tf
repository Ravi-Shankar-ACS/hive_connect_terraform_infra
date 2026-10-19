variable "account_id" {
  description = "The AWS account. Terraform refuses to run against any other."
  type        = string
}

variable "region" {
  description = "Home region."
  type        = string
  default     = "ap-south-1"
}

# --- People ---------------------------------------------------------------

variable "admin_user_arns" {
  description = "IAM users (with MFA) who may assume hive-admin."
  type        = list(string)
}

variable "developer_user_arns" {
  description = "IAM users who may assume hive-developer."
  type        = list(string)
  default     = []
}

variable "readonly_user_arns" {
  description = "IAM users who may assume hive-readonly."
  type        = list(string)
  default     = []
}

variable "protected_resource_arns" {
  description = "The running stack that hive-* roles may never change. scripts/preflight.sh lists candidates."
  type        = list(string)
}

variable "alert_emails" {
  description = "Who receives GuardDuty findings and cost anomaly alerts."
  type        = list(string)
}

# --- Security baseline (set false for anything preflight shows is already on)

variable "enable_guardduty" {
  description = "Create a GuardDuty detector. False if the account already has one."
  type        = bool
  default     = true
}

variable "guardduty_features" {
  description = "GuardDuty protection plans. Kept explicit because they bill on the whole account, old stack included."
  type        = map(string)
  default = {
    S3_DATA_EVENTS         = "ENABLED"
    RDS_LOGIN_EVENTS       = "ENABLED"
    EKS_AUDIT_LOGS         = "DISABLED"
    EBS_MALWARE_PROTECTION = "DISABLED"
    LAMBDA_NETWORK_LOGS    = "DISABLED"
    RUNTIME_MONITORING     = "DISABLED"
  }
}

variable "enable_config" {
  description = "Create an AWS Config recorder. False if the account already has one."
  type        = bool
  default     = true
}

variable "config_resource_types" {
  description = "The only resource types Config records (it cannot filter by tag, so this keeps the bill small)."
  type        = list(string)
  default = [
    "AWS::EC2::VPC",
    "AWS::EC2::Subnet",
    "AWS::EC2::SecurityGroup",
    "AWS::EC2::RouteTable",
    "AWS::EC2::InternetGateway",
    "AWS::EC2::NatGateway",
    "AWS::EC2::EIP",
    "AWS::EC2::VPCEndpoint",
    "AWS::ElasticLoadBalancingV2::LoadBalancer",
    "AWS::ElasticLoadBalancingV2::Listener",
    "AWS::WAFv2::WebACL",
    "AWS::ACM::Certificate",
    "AWS::ECS::Cluster",
    "AWS::ECS::Service",
    "AWS::ECS::TaskDefinition",
    "AWS::ECR::Repository",
    "AWS::RDS::DBInstance",
    "AWS::S3::Bucket",
    "AWS::KMS::Key",
    "AWS::SecretsManager::Secret",
    "AWS::IAM::Role",
    "AWS::IAM::Policy",
  ]
}

variable "enable_access_analyzer" {
  description = "Create an account Access Analyzer. False if one exists."
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "Create a multi-region CloudTrail trail. False if the account already has one (a second trail is billed)."
  type        = bool
  default     = true
}

variable "enable_inspector_ecr" {
  description = "Turn on Inspector image scanning on push for ECR."
  type        = bool
  default     = true
}

variable "inspector_ecr_repository_filters" {
  description = "Repositories Inspector scans on push. Once enhanced scanning is on, repositories that match nothing here are not scanned at all, so add the old stack's repositories if it uses ECR."
  type        = list(string)
  default     = ["hive-*"]
}

# --- Cost ---------------------------------------------------------------------

variable "activate_cost_tags" {
  description = "Activate the Project and Env cost-allocation tags and the cost anomaly monitor. Set true about a day after the first tagged resources exist (AWS only lists a tag once it has seen it)."
  type        = bool
  default     = false
}

variable "anomaly_threshold_usd" {
  description = "Email when a cost anomaly's impact reaches this many USD."
  type        = number
  default     = 20
}
