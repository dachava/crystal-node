# environments/dev/main.tf
# calls modules and passes in values, resources live within the modules

### [DATA] ###
data "aws_caller_identity" "current" {} # Pull the AccountID
# Crystal App API
data "aws_lb" "crystal_app" { # Fetch my LB for reference
  count = var.deploy_api_gw ? 1 : 0
  name = "crystal-app-nlb"
}

data "aws_lb_listener" "crystal_app" { # Take the ARN, find the listener
  count = var.deploy_api_gw ? 1 : 0
  load_balancer_arn = var.deploy_api_gw ? data.aws_lb.crystal_app[0].arn : ""
  port              = 80
}

# Fit-Link API
data "aws_lb" "fit_link" {
  count = var.deploy_api_gw ? 1 : 0
  name  = "fit-link-nlb"
}

data "aws_lb_listener" "fit_link" {
  count             = var.deploy_api_gw ? 1 : 0
  load_balancer_arn = var.deploy_api_gw ? data.aws_lb.fit_link[0].arn : ""
  port              = 80
}



### [PROVIDERS] ###
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
}
  }
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}


provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
  load_config_file = false
}

### [MODULES] ###
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
  count  = var.deploy_api_gw ? 1 : 0
  source = "../../modules/api-gw"

  project_name       = var.cluster_name
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  nlb_listener_arn   = var.deploy_api_gw ? data.aws_lb_listener.crystal_app[0].arn : "" # my data fetch above

  tags = local.common_tags
}

module "api_gw_fit_link" {
  count  = var.deploy_api_gw ? 1 : 0
  source = "../../modules/api-gw"

  project_name       = "fit-link"
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  nlb_listener_arn   = data.aws_lb_listener.fit_link[0].arn

  tags = local.common_tags
}

module "lb_controller" {
  source = "../../modules/lb-controller"

  cluster_name = var.cluster_name
  aws_region   = var.aws_region
  vpc_id       = module.vpc.vpc_id

  depends_on = [module.eks] # the entire module needs the EKS cluster to exist before it runs
}

# Installs the EKS Pod Identity Agent daemonset on every node. 
# agent that intercepts AWS credential requests from pods and exchanges them with the EKS API
resource "aws_eks_addon" "pod_identity" {
  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [module.eks]
}

module "route53" {
  count  = var.deploy_api_gw ? 1 : 0 # on/off switch
  source = "../../modules/route53"

  domain_name = var.domain_name
  subdomain   = "api"
  api_id      = var.deploy_api_gw ? module.api_gw[0].api_id : "" # avoid conflict if api_gw=false
  api_stage   = "dev"
  tags        = local.common_tags
}

module "route53_fit_link" {
  count  = var.deploy_api_gw ? 1 : 0
  source = "../../modules/route53"

  domain_name = var.domain_name
  subdomain   = "fit"
  api_id      = module.api_gw_fit_link[0].api_id
  api_stage   = "dev"
  tags        = local.common_tags
}

module "observability" {
  source = "../../modules/observability"

  cluster_name     = var.cluster_name
  aws_region       = var.aws_region
  grafana_password = var.grafana_password
  tags             = local.common_tags

  depends_on = [module.eks, aws_eks_addon.pod_identity]
}

module "security" {
  source = "../../modules/security"

  cluster_name        = var.cluster_name
  app_namespace       = var.app_namespace
  app_service_account = var.app_service_account
  db_password         = var.db_password
  api_key             = var.api_key
  tags                = local.common_tags

  depends_on = [module.eks]
}

module "cicd" {
  source = "../../modules/cicd"

  cluster_name = var.cluster_name
  aws_region   = var.aws_region
  account_id   = data.aws_caller_identity.current.account_id
  app_name     = var.app_name
  github_org   = var.github_org
  github_repo  = var.github_repo
  tags         = local.common_tags

  depends_on = [module.eks]
}

module "argocd" {
  source = "../../modules/argocd"

  cluster_name  = var.cluster_name
  app_name      = var.app_name
  app_namespace = var.app_namespace
  github_org    = var.github_org
  github_repo   = var.github_repo

  depends_on = [module.eks]
}