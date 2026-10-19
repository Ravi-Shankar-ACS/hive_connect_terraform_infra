# Layer 1 of 4: the VPC, its security groups and the environment's KMS keys.
# Nothing here touches the existing EKS/Aurora network or the default VPC.

data "aws_partition" "current" {}

module "network" {
  source = "../../modules/network"

  name                     = local.name
  vpc_cidr                 = var.vpc_cidr
  azs                      = var.azs
  public_subnet_cidrs      = var.public_subnet_cidrs
  app_subnet_cidrs         = var.app_subnet_cidrs
  data_subnet_cidrs        = var.data_subnet_cidrs
  app_ports                = var.app_ports
  app_egress_tcp_ports     = var.app_egress_tcp_ports
  flow_log_retention_days  = var.flow_log_retention_days
  logs_kms_key_arn         = aws_kms_key.this["app"].arn
  permissions_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${var.account_id}:policy/hive-boundary"
}
