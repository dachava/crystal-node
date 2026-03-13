# These values are consumed by other modules.
# The EKS module needs vpc_id and subnet IDs.
# The API Gateway module needs vpc_id and private subnet IDs for VPC Link.

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for LBs and NAT gateway"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes"
  value       = aws_subnet.private[*].id
}

output "vpc_cidr" {
  description = "VPC CIDR block for security group rules to allow intra-VPC traffic"
  value       = aws_vpc.main.cidr_block
}
