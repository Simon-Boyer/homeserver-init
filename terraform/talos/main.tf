terraform {
  required_version = "~> 1.3"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.4.0-alpha.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    time = {
      source = "hashicorp/time"
      version = "0.9.1"
    }
    tfe = {
      source = "hashicorp/tfe"
      version = "0.49.2"
    }
  }
}

locals {
  certSANs = var.servers_dns
}

// ------------
// TALOS
// ------------

resource "talos_machine_secrets" "secrets" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_endpoint}:6443"
  talos_version    = var.talos_version
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.secrets.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_endpoint}:6443"
  talos_version    = var.talos_version
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.secrets.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.secrets.client_configuration
  endpoints            = [var.cluster_endpoint]
}

resource "talos_machine_configuration_apply" "controlplanes" {
  for_each                    = { for s in var.servers : s.hostname => s if s.controlplane }
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = "${each.value.hostname}.${var.network_config.domain}"
  config_patches = [
    templatefile("talos/machine_config.yaml.tmpl", {
      hostname        = "${each.value.hostname}.${var.network_config.domain}"
      install_disk    = each.value.install_disk
      certSANs        = local.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id  = var.oidc-client-id
    })
  ]
}

resource "talos_machine_configuration_apply" "workers" {
  for_each                    = { for s in var.servers : s.hostname => s if !s.controlplane }
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = "${each.value.hostname}.${var.network_config.domain}"
  config_patches = [
    templatefile("talos/machine_config.yaml.tmpl", {
      hostname        = "${each.value.hostname}.${var.network_config.domain}"
      install_disk    = each.value.install_disk
      certSANs        = local.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id  = var.oidc-client-id
    })
  ]
}

resource "talos_machine_bootstrap" "bootstrap" {
  client_configuration = talos_machine_secrets.secrets.client_configuration
  node                 = var.servers[0].hostname
  endpoint             = var.cluster_endpoint
  depends_on           = [talos_machine_configuration_apply.controlplanes]
}

data "talos_cluster_health" "talos_health" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = talos_machine_secrets.secrets.client_configuration
  control_plane_nodes  = [ for i, v in var.servers : cidrhost(var.network_config.network, 3) if v.controlplane]
  endpoints            = [var.cluster_endpoint]
}

data "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on = [ data.talos_cluster_health.talos_health ]
  client_configuration = talos_machine_secrets.secrets.client_configuration
  node                 = var.servers[0].hostname
  endpoint             = var.cluster_endpoint
}

output "kubeconfig" {
  value = data.talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration
  sensitive = true
}