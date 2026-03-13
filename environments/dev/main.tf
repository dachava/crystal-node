# environments/dev/main.tf
# calls modules and passes in values, resources live within the modules

### [DATA] ###
data "aws_caller_identity" "current" {} # Pull the AccountID

data "aws_lb" "crystal_app" { # Fetch my LB for reference
  name = "crystal-app-nlb"
}

data "aws_lb_listener" "crystal_app" { # Take the ARN, find the listener
  load_balancer_arn = data.aws_lb.crystal_app.arn
  port              = 80
}


terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "../../modules/vpc"

  cluster_name         = var.cluster_name
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  tags = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  instance_type       = var.instance_type
  desired_nodes       = var.desired_nodes
  min_nodes           = var.min_nodes
  max_nodes           = var.max_nodes
  tags                = local.common_tags
}

module "s3" {
  source = "../../modules/s3"

  project_name = var.cluster_name
  environment  = "dev"
  account_id   = data.aws_caller_identity.current.account_id # Get the AccountID data
  tags         = local.common_tags
}

module "api_gw" {
  source = "../../modules/api-gw"

  project_name       = var.cluster_name
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  nlb_listener_arn   = data.aws_lb_listener.crystal_app.arn # my data fetch above

  tags = local.common_tags
}

