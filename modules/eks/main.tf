resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn # [REQUIRED] IAM role assumed by the Control Plane


vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true # API server is only reachable from inside the VPC, true for lab
    security_group_ids      = [aws_security_group.cluster.id] # SG attached to the ENIs control plane creates
  }

    # Now force the role to have its permissions before the cluster tries to create
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

### [IAM POLICIES] ###

# Trust policy only EKS can assume
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Cluster policy attachment
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" # Managed policy
}

# Trust policy only EC2 can assume
resource "aws_iam_role" "nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Node policy attachment

#lets nodes register with the cluster
resource "aws_iam_role_policy_attachment" "node_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" 
}

# VPC CNI plugin runs on every node and manages pod networking
resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# nodes can pull container images from ECR
resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

### [OIDC PROVIDER] ###

# AWS permissions for pods IRSA via OIDC
# reads the TLS certificate from the EKS OIDC issuer URL
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# registers EKS cluster as a trusted identity provider with IAM
# With OIDC + IRSA a pod gets its own IAM role scoped to exactly what it needs
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"] # tokens from OIDC provider are intended for STS
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint] #proof for OIDC
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

### [SECURITY GROUPS] ###

# Nothing can reach the API server unless explicitly allowed here
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Controls access to the EKS control plane API server"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-node-sg"
  description = "Controls traffic to and from EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-node-sg"
  })
}

# Nodes can talk to the API server on 443
resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id # only traffic coming from resources in the node SG is allowed
  description              = "Allow nodes to reach the API server"
}

# Control plane can talk back to nodes on 1025-65535
resource "aws_security_group_rule" "nodes_ingress_from_cluster" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535 # Pods get ephemeral ports
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Allow control plane to reach kubelets and pods"
}

# Nodes can talk to each other freely
resource "aws_security_group_rule" "nodes_ingress_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1" # ALL Protocols
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Allow nodes to communicate with each other"
}

# Nodes can reach the internet outbound
# pull container images from ECR, call AWS APIs, and send logs
resource "aws_security_group_rule" "nodes_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nodes.id
  description       = "Allow all outbound from nodes"
}

### [NODE GROUP] ###

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn # Trust policy defined above
  subnet_ids      = var.private_subnet_ids
  ami_type       = "AL2_x86_64"
  instance_types = [var.instance_type]
  disk_size      = 20
  scaling_config { # Values for the Autoscaler pod
    desired_size = var.desired_nodes
    min_size     = var.min_nodes
    max_size     = var.max_nodes
  }
   update_config {
    max_unavailable = 1 # 1 node taken down at the time
  }

  depends_on = [ # Again explicitly attach
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_policy
  ]
}