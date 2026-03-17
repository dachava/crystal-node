# For some reason the module pulls hashicorp/kubectl instead of gavinbunney/kubectl
# this module needs to explicitly declare the provider source
terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

### [ArgoCD namespace and Helm Release] ###
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.7.0"

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP" # access via port forward
        }
      }
      configs = {
        params = {
          "server.insecure" = true # disables TLS on the ArgoCD server internally. In PROD use ingress w/ cert
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

### [ArgoCD app] ###
resource "kubectl_manifest" "argocd_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.app_name
      namespace = "argocd"
    }
    spec = {
      project = "default"

      source = {
        repoURL        = "https://github.com/${var.github_org}/${var.github_repo}" # points Argo to the repo
        targetRevision = "master" # watches the master branch
        path           = "k8s/crystal-app" # watches the k8s/ directory specifically
      }

      destination = {
        server    = "https://kubernetes.default.svc" # In-cluster endpoint, deploys to the same cluster ArgoCD is running in
        namespace = var.app_namespace
      }

      syncPolicy = {
        automated = {
          prune    = true # delete a file from k8s/, ArgoCD deletes the corresponding resource from the cluster 
          selfHeal = true # ArgoCD automatically reverts manual changes in cluster that differ from git
        }
        syncOptions = ["CreateNamespace=true"] # ArgoCD creates the namespace if it doesn't exist
      }
    }
  })

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "argocd_fit_link" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "fit-link"
      namespace = "argocd"
    }
    spec = {
      project = "default"

      source = {
        repoURL        = "https://github.com/${var.github_org}/${var.github_repo}"
        targetRevision = "master"
        path           = "k8s/fit-link"
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "fit-link"
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  depends_on = [helm_release.argocd]
}