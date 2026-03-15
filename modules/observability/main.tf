### [Namespace] ###
# Everything observability-related lives in its own namespace: monitoring
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform" # marks it as Terraform-managed
    }
  }
}

### [Prometheus + Grafana] ###
# via kube-prometheus-stack

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack" # single chart deploys Prometheus, Grafana, pre-built K8S dashboards and alerting rules, industry standard
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "67.4.0" # Pin a version as good practice

  values = [
    yamlencode({
      grafana = {
        enabled       = true
        adminPassword = var.grafana_password

        service = {
          type = "ClusterIP" # not exposed, access via kubectl port-forward or ingress  with auth
        }
      }

      prometheus = {
        prometheusSpec = {
          retention = "7d" # keep 7 days of metrics

          resources = {
            requests = {
              cpu    = "200m" # 0.2 cores
              memory = "400Mi" # Megabytes
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }
      }

      alertmanager = { # Alertmanager handles routing alerts to Slack PagerDuty etc
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

### [CloudWatch Insights] ###
#IAM role for CW agent
resource "aws_iam_role" "cloudwatch_agent" {
  name = "${var.cluster_name}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" #AWS managed to write to CLoudWatch
}

resource "aws_eks_pod_identity_association" "cloudwatch_agent" {
  cluster_name    = var.cluster_name
  namespace       = "amazon-cloudwatch" # Separate namespace, AWS convention
  service_account = "aws-cloudwatch-metrics" # Helm chart creates the account
  role_arn        = aws_iam_role.cloudwatch_agent.arn
}

# CloudWatch agent Helm release
resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Deploys the CloudWatch agent as a daemonset one pod per node
# collects container logs, CPU, memory, network, and disk metrics and ships them to CloudWatch.
resource "helm_release" "cloudwatch_agent" {
  name       = "aws-cloudwatch-metrics" # AWS's official Helm chart for Container Insights
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-cloudwatch-metrics"
  namespace  = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
  version    = "0.0.11"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

# needs the Pod Identity association
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch,
    aws_eks_pod_identity_association.cloudwatch_agent
  ]
}