### [SUBNET GROUP] ###
# RDS must know which private subnets it can use
resource "aws_db_subnet_group" "fit_link" {
  name       = "${var.cluster_name}-fit-link-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-fit-link-subnet-group"
  })
}

### [SECURITY GROUP] ###
# Only EKS nodes may reach port 5432
resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-fit-link-rds-sg"
  description = "Controls access to the fit-link RDS instance"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-fit-link-rds-sg"
  })
}

resource "aws_security_group_rule" "rds_ingress_from_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = var.node_security_group_id
  description              = "Allow EKS nodes to reach PostgreSQL"
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound from RDS"
}

### [RDS INSTANCE] ###
resource "aws_db_instance" "fit_link" {
  identifier        = "${var.cluster_name}-fit-link"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.fit_link.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false # dev — single AZ is fine
  skip_final_snapshot = true
  apply_immediately   = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-fit-link"
  })
}

### [SECRETS MANAGER] ###
# Stores DATABASE_URL and SECRET_KEY as a JSON object
# One secret, two keys, Secrets Manager charges per secret not per key
resource "aws_secretsmanager_secret" "fit_link" {
  name                    = "${var.cluster_name}/fit-link/app-secrets"
  description             = "Application secrets for fit-link"
  recovery_window_in_days = 0 # Allows immediate deletion

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "fit_link" {
  secret_id = aws_secretsmanager_secret.fit_link.id

  secret_string = jsonencode({
    DATABASE_URL = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.fit_link.address}:${aws_db_instance.fit_link.port}/${var.db_name}"
    SECRET_KEY   = var.secret_key
  })
}

### [POD IDENTITY] ###
# IAM role the fit-link pods assume via EKS Pod Identity
resource "aws_iam_role" "fit_link" {
  name = "${var.cluster_name}-fit-link-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

# Read-only access to the fit-link secret
resource "aws_iam_policy" "secrets_access" {
  name = "${var.cluster_name}-fit-link-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_secretsmanager_secret.fit_link.arn # pod can only access this specific secret
    }]
  })
}

# Bedrock model invocation for fit-link
resource "aws_iam_policy" "bedrock_invoke" {
  name = "${var.cluster_name}-fit-link-bedrock-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fit_link_secrets" {
  role       = aws_iam_role.fit_link.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "fit_link_bedrock" {
  role       = aws_iam_role.fit_link.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

# Assoc. with Pod Identity
resource "aws_eks_pod_identity_association" "fit_link" {
  cluster_name    = var.cluster_name
  namespace       = "fit-link"
  service_account = "fit-link"
  role_arn        = aws_iam_role.fit_link.arn
}
