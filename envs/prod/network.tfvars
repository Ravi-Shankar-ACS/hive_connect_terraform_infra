# Production network: 10.30.0.0/16 does not overlap the EKS/Aurora network
# (192.168.0.0/16) or the default VPC (172.31.0.0/16), so it can be peered later.

vpc_cidr = "10.30.0.0/16"
azs      = ["ap-south-1a", "ap-south-1b"]

public_subnet_cidrs = ["10.30.0.0/24", "10.30.1.0/24"]   # ALB, NAT gateway
app_subnet_cidrs    = ["10.30.16.0/22", "10.30.20.0/22"] # Fargate tasks
data_subnet_cidrs   = ["10.30.32.0/24", "10.30.33.0/24"] # RDS, no internet route
# Reserved for a third AZ (ap-south-1c): 10.30.2.0/24, 10.30.24.0/22, 10.30.34.0/24

# Container ports: hiveconnect-api 8000, prism 8080 (plan open question 4).
app_ports = [8000, 8080]

# Outbound from the tasks through NAT. The plan allows 443 only. If SMTP uses
# 587/465 or devices' MQTT broker needs 8883, add those ports here.
app_egress_tcp_ports = [443]

flow_log_retention_days = 14
