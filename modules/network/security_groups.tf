# Each tier talks only to the next one:
#   internet --443/80--> alb-sg --app ports--> app-sg --5432--> db-sg
# No rule opens the database to 0.0.0.0/0 and no admin port is open anywhere
# (use ECS Exec instead of SSH).

locals {
  app_ports    = toset([for p in var.app_ports : tostring(p)])
  egress_ports = toset([for p in var.app_egress_tcp_ports : tostring(p)])
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB: HTTPS and HTTP from the internet, app ports to app-sg"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app-sg"
  description = "Fargate tasks: app ports from alb-sg only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db-sg"
  description = "RDS: PostgreSQL from app-sg only, no outbound"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-db-sg" }
}

# --- alb-sg ---------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet, redirected to HTTPS by the listener"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  for_each = local.app_ports

  security_group_id            = aws_security_group.alb.id
  description                  = "To the app tasks on port ${each.value}"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
}

# --- app-sg ---------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  for_each = local.app_ports

  security_group_id            = aws_security_group.app.id
  description                  = "From the ALB on port ${each.value}"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
}

resource "aws_vpc_security_group_egress_rule" "app_to_internet" {
  for_each = local.egress_ports

  security_group_id = aws_security_group.app.id
  description       = "Outbound TCP ${each.value} through the NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL to the database"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

# --- db-sg ----------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the app tasks"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}
