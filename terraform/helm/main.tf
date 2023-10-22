terraform {
  required_version = "~> 1.3"
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "3.3.0"
    }
    helm = {
      source = "hashicorp/helm"
      version = "2.11.0"
    }
    kubectl = {
      source = "alekc/kubectl"
      version = "2.0.3"
    }
  }
}

// ------------
// MetalLB
// ------------

resource "helm_release" "metallb" {
  name       = "metallb"

  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version = var.metallb_version
  namespace = "metallb-system"
  create_namespace = true
}

resource "kubectl_manifest" "bgp_peer" {
  yaml_body = <<EOF
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: router
  namespace: metallb-system
spec:
  myASN: ${var.network_config.bgp_cluster_as}
  peerASN: ${var.network_config.bgp_router_as}
  peerAddress: ${cidrhost(var.network_config.network, 1)}
EOF

  depends_on = [ helm_release.metallb ]
}

// ------------
// ArgoCD
// ------------

resource "helm_release" "argocd" {
  name       = "argocd"

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version = var.argocd_version
  namespace = "argocd"
  create_namespace = true

  set {
    name = "server.service.type"
    value = "NodePort"
  }

  set {
    name = "configs.secret.argocdServerAdminPassword"
    value = bcrypt(var.argocd_password)
  }
}

resource "kubectl_manifest" "argocd_bootstrap" {
  yaml_body = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: argocd
    server: https://kubernetes.default.svc
  project: default
  source:
    path: argocd
    repoURL: ${var.git_repo}
    targetRevision: main
  syncPolicy:
    automated:
      selfHeal: true
EOF

  depends_on = [ helm_release.argocd ]
}