### [Data Sources] ###
# EKS CLuster details, OIDC issuer URL
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

#  OIDC provider created in EKS module to fetch ARN for the trust policy
# data "aws_iam_openid_connect_provider" "main" {
#   url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
# }

### [IAM TRust policy] ###
# Generates a JSON policy document
data "aws_iam_policy_document" "lb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Pod Identity Association
# wires a pod to an IAM role
# any pod in kube-system using the aws-load-balancer-controller service account should assume this IAM role
resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.cluster_name}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_trust.json
}

### [IAM Policy Attachment] ###
resource "aws_iam_policy" "lb_controller" {
  name   = "${var.cluster_name}-lb-controller-policy"
  policy = file("${path.module}/iam_policy.json") # reads the policy JSON from module's dir
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

### [K8S SERVICE ACCOUNT] ###
# Provider in action, I LOVE this block
# Replaces manual work:
# eksctl create iamserviceaccount
# kubectl create serviceaccount
# kubectl annotate serviceaccount

resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    # # [REQUIRED] IRSA annotation to link K8S service account to IAM ROle
    # annotations = {
    #   "eks.amazonaws.com/role-arn" = aws_iam_role.lb_controller.arn
    # }

    labels = { # [REQUIRED] Helm chart looks for them
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
  }
    # depend on the IAM role and policy fully attached
  depends_on = [aws_iam_role_policy_attachment.lb_controller]
}

### [HELM RELEASE] ###
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.11.0" # Always specify a version

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create" 
    value = "false" # Already created the service account earlier
  }

  set {
    name  = "serviceAccount.name" # Reference the account instead
    value = kubernetes_service_account.lb_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }
    # Helm must wait for the service account to exist before deploying
  depends_on = [kubernetes_service_account.lb_controller]
}