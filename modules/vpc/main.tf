# modules/vpc/main.tf
# [BUILDS]:
#   - 1 VPC
#   - 2 public subnets  (API Gateway, NAT Gateway, Load Balancers)
#   - 2 private subnets (EKS nodes)
#   - 1 Internet Gateway (public subnets > internet)
#   - 1 Elastic IP for NAT
#   - 1 NAT Gateway      (private subnets > internet one-way)
#   - Route Tables
#

#   EKS worker nodes pull container images and call AWS APIs via NAT
#   but nothing on the internet can reach them

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # EKS nodes register by hostname
  enable_dns_support   = true  # EKS internal DNS resolution

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpc"

    # REQUIRED by EKS cluster to discover which VPC it belongs to
    # when creating load balancers and network interfaces
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# Internet Gateway
# Allows resources in public subnets to reach the internet and be reached
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-igw"
  })
}

# PUBLIC Subnets
# One per AZ for high availability
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # true means any EC2 here gets a public IP

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-public-${var.availability_zones[count.index]}"

    # [TAG] AWS Load Balancer Controller
    # create internet-facing load balancers in these subnets
    "kubernetes.io/role/elb" = "1"

    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# PRIVATE Subnets
# EKS Outbound traffic goes via NAT
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-private-${var.availability_zones[count.index]}"

    # [TAG] AWS Load Balancer Controller
    # create internal load balancers in these subnets
    "kubernetes.io/role/internal-elb" = "1"

    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# Elastic IP for NAT Gateway
# NAT Gateway needs a static public IP so outbound traffic from private subnets
resource "aws_eip" "nat" {
  domain = "vpc"  # So it doesn't default to EC2

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nat-eip"
  })

  # EIP must be created after the IGW exists
  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway
# [IMPORTANT] Sits in a PUBLIC subnet. Private subnet nodes route outbound traffic here
# NAT rewrites the source IP to the EIP, sends it out via the IGW
# Return traffic is tracked by NAT and forwarded back to the originating node

# $$$$$$$ ONLY 1 BECAUSE $$$$$$$
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id  # always in the first public subnet

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
# [RULE] all traffic not destined for the VPC 0.0.0.0/0 goes to the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-public-rt"
  })
}

# Associate the public route table with every public subnet
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
# [RULE] all outbound traffic goes to the NAT Gateway (not the IGW directly)
# The NAT then forwards it out via the IGW on behalf of the private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-private-rt"
  })
}

# Associate the private route table with every private subnet
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
