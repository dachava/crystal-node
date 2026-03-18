### [ECR REPOSITORY] ###
#ECR: AWS container registry, stores Docker images
# the repository name, Images will be pushed to:
# <account-id>.dkr.ecr.us-east-1.amazonaws.com/crystal-app or <your-app>
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE" # For lab MUTABLE, IMMUTABLE use tags with the git SHA as the tag
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true # every image pushed to ECR gets scanned for known CVEs auto
  }

  tags = var.tags
}

resource "aws_ecr_repository" "fit_link" {
  name                 = "fit-link"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# Lifecycle policy
# Without this, ECR accumulates every image ever pushed
# Useful to cap storage costs ex. last N images based on how far back it's needed to roll back
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "fit_link" {
  repository = aws_ecr_repository.fit_link.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# [IMPORTANT]: EKS uses two authorization layers
# 1. IAM determines if you can call EKS APIs
# 2. aws-auth ConfigMap determines what you can do inside the cluster via Kubernetes RBAC

### [IAM Role GitHub Actions] ###
# pure OIDC federation NO AWS access keys

# register GitHub as a trusted OIDC provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com" # GitHub's OIDC endpoint, job gets a JWT
  client_id_list  = ["sts.amazonaws.com"] # same as EKS OIDC, token for STS
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's root CA thumbprint
}

# ASsume role
resource "aws_iam_role" "github_actions" {
  name = "${var.cluster_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # token must be intended for STS
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # allows any branch or event only on the specific repo to assume this role
        StringLike = {
  "token.actions.githubusercontent.com:sub" = [
    "repo:${var.github_org}/${var.github_repo}:*",
    "repo:${var.github_org}/fit-link:*"
  ]
}
      }
    }]
  })
}

# ROle Permissions
resource "aws_iam_policy" "github_actions" {
  name = "${var.cluster_name}-github-actions-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken" # gets a Docker login token for ECR
        ]
        Resource = "*" # Must be * because it's an account level action not a resource one
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
         Resource = [ # push permissions on the specific repo ARN
    aws_ecr_repository.app.arn, 
    aws_ecr_repository.fit_link.arn
  ] 
      },
      {
        Effect = "Allow"
        Action = [ # Without this the pipeline can't connect to the cluster
          "eks:DescribeCluster" # needed by kubectl to get the cluster endpoint and certificate
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${var.account_id}:cluster/${var.cluster_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

### [EKS Access for GitHub Actions] ###
# EKS has its own authorization layer on top of IAM called aws-auth ConfigMap 

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth" # ConfigMap: this is how EKS maps IAM roles to Kubernetes RBAC permissions
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = "arn:aws:iam::${var.account_id}:role/${var.cluster_name}-node-role"
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = aws_iam_role.github_actions.arn
        username = "github-actions"
        groups   = ["system:masters"] # gives GitHub Actions full cluster admin
        # On PROD  create a specific ClusterRole with only the permissions the pipeline needs 
      }
    ])
  }

  force = true # tells the Kubernetes provider to update the existing data instead of failing because it already exists
}

