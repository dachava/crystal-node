### [NETWORK POLICIES] ###
# default: deny all inbound
# exception: allow port 80 to app pods
# outbound: allow everything

resource "kubernetes_network_policy" "deny_all_ingress" {
  metadata {
    name      = "deny-all-ingress"
    namespace = var.app_namespace
  }

  spec {
    pod_selector {} # Empty means to apply to ALL pods in namespace

    policy_types = ["Ingress"] # COntrol inbound traffic only
    # No ingress rules = Deny ALL inbound traffic as baseline
  }
}

resource "kubernetes_network_policy" "allow_ingress_from_nlb" {
  metadata {
    name      = "allow-ingress-from-nlb"
    namespace = var.app_namespace
  }

  spec {
    pod_selector {
      match_labels = {
        app = "crystal-app" # policy only applies to pods with app's label
      }
    }

    policy_types = ["Ingress"]
    # only NLB can reach these ports anyway
    ingress {
      ports {
        port     = "80" # explicitly allows inbound traffic on port 80
        protocol = "TCP"
      }
    }
  }
}

# Pods need to reach AWS APIs, DNS, and other services
# Locking down egress is possible but adds significant complexity
resource "kubernetes_network_policy" "allow_egress" {
  metadata {
    name      = "allow-all-egress"
    namespace = var.app_namespace
  }

  spec {
    pod_selector {}

    policy_types = ["Egress"] # allow ALL outbound

    egress {}
  }
}

### [POD SECURITY STANDARDS] ###
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace
    # Labels built in K8S
    labels = {
      # Enforce pod security at the namespace level
      # Three modes: enforce, audit, warn
      # Three levels: privileged, baseline, restricted
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

### [SECRETS MANAGER] ###
resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.cluster_name}/${var.app_namespace}/app-secrets"
  description             = "Application secrets for crystal-app"
  recovery_window_in_days = 0 # Allows immediate deletion

  tags = var.tags
}

# stores secrets as a JSON object
# One secret, multiple key/value pairs inside it
# Secrets Manager charges per secret not per key
resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    db_password = var.db_password
    api_key     = var.api_key
  })
}

# IAM Role for the pods
resource "aws_iam_role" "app" {
  name = "${var.cluster_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_policy" "secrets_access" {
  name = "${var.cluster_name}-app-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue", # READ-ONLY values
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_secretsmanager_secret.app.arn # The pod can only access this specific secret
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_secrets" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

# Wiring up with Pod Identity
resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = var.cluster_name
  namespace       = var.app_namespace
  service_account = var.app_service_account
  role_arn        = aws_iam_role.app.arn
}