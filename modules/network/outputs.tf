output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnets, in AZ order."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "app_subnet_ids" {
  description = "App subnets, in AZ order."
  value       = [for az in var.azs : aws_subnet.app[az].id]
}

output "data_subnet_ids" {
  description = "Data subnets, in AZ order."
  value       = [for az in var.azs : aws_subnet.data[az].id]
}

output "alb_security_group_id" {
  description = "alb-sg."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "app-sg."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "db-sg."
  value       = aws_security_group.db.id
}

output "nat_gateway_id" {
  description = "NAT gateway ID, for the port-allocation alarm."
  value       = aws_nat_gateway.this.id
}

output "nat_public_ip" {
  description = "Outbound address of every task. Third parties that filter by IP must allowlist it."
  value       = aws_eip.nat.public_ip
}
