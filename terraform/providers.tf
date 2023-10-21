terraform {
  required_version = "~> 1.3"
  required_providers {
    helm = {
      source = "hashicorp/helm"
      version = "2.11.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.13.2"
    }
    kubectl = {
      source = "alekc/kubectl"
      version = "2.0.3"
    }
  }
  cloud {
    organization = "Simon-Boyer"
    workspaces {
      name = "homelab"
    }
  }
}

provider "kubectl" {
  host = var.kubeconfig.host
  cluster_ca_certificate = base64decode(var.kubeconfig.ca_certificate)
  client_certificate = base64decode(var.kubeconfig.client_certificate)
  client_key = base64decode(var.kubeconfig.client_key)
  load_config_file = false
}

provider "helm" {
  kubernetes {
    host = var.kubeconfig.host
    cluster_ca_certificate = base64decode(var.kubeconfig.ca_certificate)
    client_certificate = base64decode(var.kubeconfig.client_certificate)
    client_key = base64decode(var.kubeconfig.client_key)
  }
}

provider "routeros" {
  hosturl  = "https://${var.router_host}" # Or set MIKROTIK_HOST environment variable
  username = var.router_user              # Or set MIKROTIK_USER environment variable
  password = var.router_password          # Or set MIKROTIK_PASSWORD environment variable
  insecure = true                         # Or set MIKROTIK_INSECURE environment variable
}

provider "routeros" {
  alias    = "switch"
  hosturl  = "https://${var.switch_host}" # Or set MIKROTIK_HOST environment variable
  username = var.switch_user              # Or set MIKROTIK_USER environment variable
  password = var.switch_password          # Or set MIKROTIK_PASSWORD environment variable
  insecure = true                         # Or set MIKROTIK_INSECURE environment variable
}